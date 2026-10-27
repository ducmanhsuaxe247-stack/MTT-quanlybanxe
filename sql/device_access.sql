begin;
create table public.mtt_device_requests(
 id uuid primary key, secret_hash text not null check(secret_hash ~ '^[0-9a-f]{64}$'),
 full_name text not null, email text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 granted_role text check(granted_role in ('sales','editor')), requested_at timestamptz not null default now(),
 reviewed_at timestamptz, reviewed_by uuid references auth.users(id), user_id uuid references auth.users(id)
);
alter table public.mtt_device_requests enable row level security;
revoke all on public.mtt_device_requests from public,anon,authenticated;
create function mtt_private.request_device(p_id uuid,p_hash text,p_email text,p_name text) returns void
language plpgsql security definer set search_path='' as $$
declare e text:=lower(trim(p_email)); n text:=trim(p_name);
begin
 if p_id is null or p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or e is null or length(e)>254 or e !~ '^[a-z0-9._%+\-]+@gmail\.com$' or n is null or length(n)<2 or length(n)>100 then raise exception 'MTT_INVALID_REQUEST'; end if;
 perform pg_advisory_xact_lock(2472602);
 if exists(select 1 from public.mtt_device_requests where id=p_id and secret_hash=p_hash and email=e) then return; end if;
 if exists(select 1 from auth.users where id=p_id) or exists(select 1 from public.mtt_device_requests where id=p_id) then raise exception 'MTT_INVALID_REQUEST'; end if;
 if (select count(*) from public.mtt_device_requests where requested_at>now()-interval '1 day')>=100 then raise exception 'MTT_REQUEST_LIMIT'; end if;
 insert into public.mtt_device_requests(id,secret_hash,email,full_name) values(p_id,p_hash,e,n);
end $$;
create function public.mtt_request_device(p_id uuid,p_hash text,p_email text,p_name text) returns void language sql security invoker set search_path='' as $$select mtt_private.request_device(p_id,p_hash,p_email,p_name)$$;
create function mtt_private.review_device(p_id uuid,p_role text) returns void
language plpgsql security definer set search_path='' as $$
declare r public.mtt_device_requests;
begin
 if not exists(select 1 from public.mtt_profiles where user_id=auth.uid() and approved and role='owner') then raise exception 'MTT_DENIED'; end if;
 if p_role is null or p_role not in ('sales','editor','rejected') then raise exception 'MTT_INVALID_REQUEST'; end if;
 select * into r from public.mtt_device_requests where id=p_id for update;
 if not found then raise exception 'MTT_INVALID_REQUEST'; end if;
 if exists(select 1 from public.mtt_profiles where user_id=r.user_id and role='owner') then raise exception 'MTT_OWNER_PROTECTED'; end if;
 update public.mtt_device_requests set status=case when p_role='rejected' then 'rejected' else 'approved' end,granted_role=case when p_role='rejected' then null else p_role end,reviewed_at=now(),reviewed_by=auth.uid() where id=p_id;
 if r.user_id is not null then update public.mtt_profiles set approved=(p_role<>'rejected'),role=case when p_role='rejected' then role else p_role end where user_id=r.user_id; end if;
end $$;
create function public.mtt_review_device(p_id uuid,p_role text) returns void language sql security invoker set search_path='' as $$select mtt_private.review_device(p_id,p_role)$$;
create or replace function mtt_private.list_requests() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.mtt_profiles where user_id=auth.uid() and approved and role='owner') then raise exception 'MTT_DENIED'; end if;
 return coalesce((select jsonb_agg(x order by (x->>'status'='pending') desc,x->>'requested_at' desc) from (
 select (to_jsonb(d)-'secret_hash')||jsonb_build_object('kind','device') as x from public.mtt_device_requests d
 union all select to_jsonb(r)||jsonb_build_object('kind','email') from public.mtt_access_requests r) q),'[]'::jsonb);
end $$;
-- Server-only bridge; never grant these to browser roles. No typed email is trusted as identity.
create function public.mtt_device_authorize(p_id uuid,p_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.mtt_device_requests;
begin
 select * into r from public.mtt_device_requests where id=p_id and secret_hash=p_hash;
 if not found then raise exception 'MTT_DENIED'; end if;
 return jsonb_build_object('status',r.status,'exists',exists(select 1 from auth.users where id=p_id and email=p_id::text||'@device.mtt.invalid'));
end $$;
create function public.mtt_activate_device(p_id uuid,p_hash text) returns void
language plpgsql security definer set search_path='' as $$
declare r public.mtt_device_requests;
begin
 select * into r from public.mtt_device_requests where id=p_id and secret_hash=p_hash and status='approved' for update;
 if not found or not exists(select 1 from auth.users where id=p_id and email=p_id::text||'@device.mtt.invalid') then raise exception 'MTT_DENIED'; end if;
 if exists(select 1 from public.mtt_profiles where user_id=p_id and role='owner') then raise exception 'MTT_OWNER_PROTECTED'; end if;
 insert into public.mtt_profiles(user_id,full_name,role,approved) values(p_id,r.full_name,r.granted_role,true) on conflict(user_id) do update set full_name=excluded.full_name,role=excluded.role,approved=true;
 update public.mtt_device_requests set user_id=p_id where id=p_id;
end $$;
revoke all on function mtt_private.request_device(uuid,text,text,text),mtt_private.review_device(uuid,text),public.mtt_request_device(uuid,text,text,text),public.mtt_review_device(uuid,text),public.mtt_device_authorize(uuid,text),public.mtt_activate_device(uuid,text) from public,anon,authenticated;
grant execute on function mtt_private.request_device(uuid,text,text,text),public.mtt_request_device(uuid,text,text,text) to anon,authenticated;
grant execute on function mtt_private.review_device(uuid,text),public.mtt_review_device(uuid,text) to authenticated;
grant execute on function public.mtt_device_authorize(uuid,text),public.mtt_activate_device(uuid,text) to service_role;
commit;
