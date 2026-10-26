begin;
create schema if not exists mtt_private;
revoke all on schema mtt_private from public,anon,authenticated;
create table if not exists public.mtt_access_requests(
 id uuid primary key default gen_random_uuid(), email text not null unique,
 full_name text not null, status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_at timestamptz not null default now(), reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id), granted_role text check(granted_role in ('sales','editor')),
 user_id uuid references auth.users(id)
);
alter table public.mtt_access_requests enable row level security;
revoke all on public.mtt_access_requests from public,anon,authenticated;
create or replace function mtt_private.request_access(p_email text,p_name text) returns void
language plpgsql security definer set search_path='' as $$
declare e text:=lower(trim(p_email)); n text:=trim(p_name);
begin
 if e is null or length(e)>254 or e !~ '^[a-z0-9._%+\-]+@gmail\.com$' or n is null or length(n)<2 or length(n)>100 then raise exception 'MTT_INVALID_REQUEST'; end if;
 -- Identical submissions never overwrite a reviewed identity or create duplicates.
 if exists(select 1 from public.mtt_access_requests where email=e) then return; end if;
 perform pg_advisory_xact_lock(2472601);
 if (select count(*) from public.mtt_access_requests where requested_at>now()-interval '1 day')>=100 then raise exception 'MTT_REQUEST_LIMIT'; end if;
 insert into public.mtt_access_requests(email,full_name) values(e,n) on conflict(email) do nothing;
end $$;
create or replace function public.mtt_request_access(p_email text,p_name text) returns void
language sql security invoker set search_path='' as $$ select mtt_private.request_access(p_email,p_name) $$;
create or replace function mtt_private.list_requests() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.mtt_profiles where user_id=auth.uid() and approved and role='owner') then raise exception 'MTT_DENIED'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by (r.status='pending') desc,r.requested_at desc) from public.mtt_access_requests r),'[]'::jsonb);
end $$;
create or replace function public.mtt_list_requests() returns jsonb language sql security invoker set search_path='' as $$select mtt_private.list_requests()$$;
create or replace function mtt_private.review_request(p_id uuid,p_role text) returns void
language plpgsql security definer set search_path='' as $$
declare r public.mtt_access_requests; u uuid;
begin
 if not exists(select 1 from public.mtt_profiles where user_id=auth.uid() and approved and role='owner') then raise exception 'MTT_DENIED'; end if;
 if p_role is null or p_role not in ('sales','editor','rejected') then raise exception 'MTT_INVALID_REQUEST'; end if;
 select * into r from public.mtt_access_requests where id=p_id for update;
 if not found then raise exception 'MTT_INVALID_REQUEST'; end if;
 select id into u from auth.users where lower(email)=r.email and email_confirmed_at is not null;
 if exists(select 1 from public.mtt_profiles where user_id=u and role='owner') then raise exception 'MTT_OWNER_PROTECTED'; end if;
 update public.mtt_access_requests set status=case when p_role='rejected' then 'rejected' else 'approved' end,
 granted_role=case when p_role='rejected' then null else p_role end,reviewed_at=now(),reviewed_by=auth.uid(),user_id=u where id=p_id;
 if u is not null then
  if p_role='rejected' then update public.mtt_profiles set approved=false where user_id=u;
  else insert into public.mtt_profiles(user_id,full_name,role,approved) values(u,r.full_name,p_role,true)
  on conflict(user_id) do update set full_name=excluded.full_name,role=excluded.role,approved=true; end if;
 end if;
end $$;
create or replace function public.mtt_review_request(p_id uuid,p_role text) returns void language sql security invoker set search_path='' as $$select mtt_private.review_request(p_id,p_role)$$;
create or replace function mtt_private.claim_access() returns text
language plpgsql security definer set search_path='' as $$
declare e text; r public.mtt_access_requests;
begin
 if auth.uid() is null then raise exception 'MTT_DENIED'; end if;
 if exists(select 1 from public.mtt_profiles where user_id=auth.uid() and role='owner' and approved) then return 'approved'; end if;
 select lower(email) into e from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if e is null then raise exception 'MTT_EMAIL_UNVERIFIED'; end if;
 select * into r from public.mtt_access_requests where email=e for update;
 if not found then return 'missing'; end if;
 if r.status='approved' then
  insert into public.mtt_profiles(user_id,full_name,role,approved) values(auth.uid(),r.full_name,r.granted_role,true)
  on conflict(user_id) do update set full_name=excluded.full_name,role=excluded.role,approved=true where public.mtt_profiles.role<>'owner';
  update public.mtt_access_requests set user_id=auth.uid() where id=r.id;
 end if;
 return r.status;
end $$;
create or replace function public.mtt_claim_access() returns text language sql security invoker set search_path='' as $$select mtt_private.claim_access()$$;
revoke all on all functions in schema mtt_private from public,anon,authenticated;
grant usage on schema mtt_private to anon,authenticated;
grant execute on function mtt_private.request_access(text,text) to anon,authenticated;
grant execute on function mtt_private.list_requests(),mtt_private.review_request(uuid,text),mtt_private.claim_access() to authenticated;
revoke all on function public.mtt_request_access(text,text),public.mtt_list_requests(),public.mtt_review_request(uuid,text),public.mtt_claim_access() from public,anon,authenticated;
grant execute on function public.mtt_request_access(text,text) to anon,authenticated;
grant execute on function public.mtt_list_requests(),public.mtt_review_request(uuid,text),public.mtt_claim_access() to authenticated;

create or replace function public.mtt_load() returns jsonb
language plpgsql security definer set search_path=public as $$
declare p public.mtt_profiles; s public.mtt_app_state; result jsonb;
begin
 select * into p from public.mtt_profiles where user_id=auth.uid() and approved;
 if p.user_id is null then raise exception 'MTT_DENIED'; end if;
 select * into s from public.mtt_app_state where id=1;
 result:=s.data;
 if p.role not in ('owner','editor') then
  result:=jsonb_build_object(
   'bikes',coalesce((select jsonb_agg(jsonb_build_object('id',b->'id','brand',b->'brand','model',b->'model','year',b->'year','color',b->'color','plate',b->'plate','price',b->'price','qty',b->'qty')) from jsonb_array_elements(s.data->'bikes') b),'[]'::jsonb),
   'sales',coalesce((select jsonb_agg(b-'cost') from jsonb_array_elements(s.data->'sales') b where b->>'actor'=auth.uid()::text),'[]'::jsonb),
   'expenses','[]'::jsonb,'targets','[]'::jsonb);
 end if;
 return jsonb_build_object('data',result,'revision',s.revision,'profile',jsonb_build_object('full_name',p.full_name,'role',p.role));
end $$;

create or replace function public.mtt_save(p_data jsonb,p_revision integer) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v integer;
begin
 if not exists(select 1 from public.mtt_profiles where user_id=auth.uid() and approved and role in ('owner','editor')) then raise exception 'MTT_DENIED'; end if;
 if not public.mtt_validate(p_data) then raise exception 'MTT_INVALID_DATA'; end if;
 select revision into v from public.mtt_app_state where id=1 for update;
 if p_revision is null or v<>p_revision then raise exception 'MTT_CONFLICT'; end if;
 update public.mtt_app_state set data=p_data,revision=v+1,updated_at=now() where id=1;
 insert into public.mtt_change_log(actor,action,revision) values(auth.uid(),'save',v+1);
 return public.mtt_load();
end $$;

create or replace function public.mtt_record_sale(p_sale jsonb,p_revision integer) returns jsonb
language plpgsql security definer set search_path=public as $$
declare p public.mtt_profiles; s public.mtt_app_state; bike jsonb; sale jsonb; q numeric; price numeric;
begin
 select * into p from public.mtt_profiles where user_id=auth.uid() and approved and role in ('owner','editor','sales');
 if p.user_id is null then raise exception 'MTT_DENIED'; end if;
 if jsonb_typeof(p_sale->'id') is distinct from 'string' or (p_sale->>'id') !~ '^[A-Za-z0-9_-]{1,80}$' then raise exception 'MTT_INVALID_DATA'; end if;
 select * into s from public.mtt_app_state where id=1 for update;
 -- Retrying the same confirmed request must not deduct inventory twice.
 if exists(select 1 from jsonb_array_elements(s.data->'sales') b where b->>'id'=p_sale->>'id' and b->>'actor'=auth.uid()::text) then return public.mtt_load(); end if;
 if p_revision is null or s.revision<>p_revision then raise exception 'MTT_CONFLICT'; end if;
 if exists(select 1 from jsonb_array_elements(s.data->'sales') b where b->>'id'=p_sale->>'id') then raise exception 'MTT_INVALID_DATA'; end if;
 if jsonb_typeof(p_sale->'qty') is distinct from 'number' or jsonb_typeof(p_sale->'price') is distinct from 'number' then raise exception 'MTT_INVALID_DATA'; end if;
 q:=(p_sale->>'qty')::numeric;price:=(p_sale->>'price')::numeric;
 if q<1 or q<>trunc(q) or price<0 or price>1e14 then raise exception 'MTT_INVALID_DATA'; end if;
 select b into bike from jsonb_array_elements(s.data->'bikes') b where b->>'id'=p_sale->>'bikeId';
 if bike is null or q>(bike->>'qty')::numeric then raise exception 'MTT_STOCK'; end if;
 sale:=jsonb_build_object('id',p_sale->>'id','bikeId',bike->>'id','brand',bike->>'brand','model',bike->>'model','plate',bike->>'plate','qty',q,'price',price,'cost',(bike->>'cost')::numeric+(bike->>'repair')::numeric,'date',p_sale->>'date','note',coalesce(p_sale->>'note',''),'seller',case when p.role in ('owner','editor') then coalesce(nullif(p_sale->>'seller',''),p.full_name) else p.full_name end,'actor',auth.uid()::text);
 s.data:=jsonb_set(s.data,'{bikes}',(select jsonb_agg(case when b->>'id'=bike->>'id' then jsonb_set(b,'{qty}',to_jsonb((b->>'qty')::numeric-q)) else b end) from jsonb_array_elements(s.data->'bikes') b));
 s.data:=jsonb_set(s.data,'{sales}',(s.data->'sales')||jsonb_build_array(sale));
 if not public.mtt_validate(s.data) then raise exception 'MTT_INVALID_DATA'; end if;
 update public.mtt_app_state set data=s.data,revision=s.revision+1,updated_at=now() where id=1;
 insert into public.mtt_change_log(actor,action,revision) values(auth.uid(),'sale',s.revision+1);
 return public.mtt_load();
end $$;
commit;
