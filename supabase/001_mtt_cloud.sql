-- Additive migration: does not modify existing vehicles/sales/expenses/targets tables.
-- One store per Supabase project. The JSON format preserves existing MTT backups and IDs.
begin;
create table if not exists public.mtt_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', phone text,
 role text not null default 'sales' check(role in ('owner','editor','sales','viewer')),
 approved boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.mtt_app_state (
 id integer primary key check(id=1), revision integer not null default 0,
 data jsonb not null default '{"bikes":[],"sales":[],"expenses":[],"targets":[]}',
 updated_at timestamptz not null default now()
);
insert into public.mtt_app_state(id) values(1) on conflict do nothing;
create table if not exists public.mtt_change_log (
 id bigint generated always as identity primary key, actor uuid not null,
 action text not null, revision integer not null, created_at timestamptz not null default now()
);
alter table public.mtt_app_state enable row level security;
alter table public.mtt_profiles enable row level security;
alter table public.mtt_change_log enable row level security;
revoke all on public.mtt_app_state,public.mtt_change_log from public,anon,authenticated;
-- Existing profile policies cannot grant privileges after this revocation.
revoke all on public.mtt_profiles from public,anon,authenticated;

create or replace function public.mtt_validate(p_data jsonb) returns boolean
language plpgsql immutable set search_path=public as $$
declare section text; item jsonb; field text; nums text[]; texts text[];
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>15728640 then return false; end if;
 foreach section in array array['bikes','sales','expenses','targets'] loop
  if jsonb_typeof(p_data->section) is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_data->section)>50000 then return false; end if;
  if (select count(*)<>count(distinct value->>'id') from jsonb_array_elements(p_data->section)) then return false; end if;
  nums:=case section when 'bikes' then array['cost','price','repair','qty'] when 'sales' then array['qty','price','cost'] when 'expenses' then array['amount'] else array['qty','money'] end;
  texts:=case section when 'bikes' then array['brand','model'] when 'sales' then array['bikeId','brand','model','seller','date'] when 'expenses' then array['type','date'] else array['name','month'] end;
  for item in select value from jsonb_array_elements(p_data->section) loop
   if jsonb_typeof(item) is distinct from 'object' or jsonb_typeof(item->'id') is distinct from 'string' or (item->>'id') !~ '^[A-Za-z0-9_-]{1,80}$' then return false; end if;
   foreach field in array nums loop
    if jsonb_typeof(item->field) is distinct from 'number' then return false; end if;
    if (item->>field)::numeric<0 or (item->>field)::numeric>1e14 then return false; end if;
   end loop;
   foreach field in array texts loop
    if jsonb_typeof(item->field) is distinct from 'string' or length(item->>field)>2000 then return false; end if;
   end loop;
   if item ? 'qty' and (item->>'qty')::numeric<>trunc((item->>'qty')::numeric) then return false; end if;
   if section='sales' and (item->>'qty')::numeric<1 then return false; end if;
   if item ? 'date' then
    if (item->>'date') !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
    perform (item->>'date')::date;
   end if;
   if item ? 'month' and (item->>'month') !~ '^\d{4}-(0[1-9]|1[0-2])$' then return false; end if;
   if item ? 'photo' and coalesce(item->>'photo','')<>'' and (item->>'photo') !~ '^data:image/(jpeg|png|webp|gif);base64,[A-Za-z0-9+/=]+$' then return false; end if;
  end loop;
 end loop;
 return true;
exception when others then return false;
end $$;

create or replace function public.mtt_load() returns jsonb
language plpgsql security definer set search_path=public as $$
declare p public.mtt_profiles; s public.mtt_app_state; result jsonb;
begin
 select * into p from public.mtt_profiles where user_id=auth.uid() and approved;
 if p.user_id is null then raise exception 'MTT_DENIED'; end if;
 select * into s from public.mtt_app_state where id=1;
 result:=s.data;
 if p.role<>'owner' then
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
 if not exists(select 1 from public.mtt_profiles where user_id=auth.uid() and approved and role='owner') then raise exception 'MTT_DENIED'; end if;
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
 sale:=jsonb_build_object('id',p_sale->>'id','bikeId',bike->>'id','brand',bike->>'brand','model',bike->>'model','plate',bike->>'plate','qty',q,'price',price,'cost',(bike->>'cost')::numeric+(bike->>'repair')::numeric,'date',p_sale->>'date','note',coalesce(p_sale->>'note',''),'seller',case when p.role='owner' then coalesce(nullif(p_sale->>'seller',''),p.full_name) else p.full_name end,'actor',auth.uid()::text);
 s.data:=jsonb_set(s.data,'{bikes}',(select jsonb_agg(case when b->>'id'=bike->>'id' then jsonb_set(b,'{qty}',to_jsonb((b->>'qty')::numeric-q)) else b end) from jsonb_array_elements(s.data->'bikes') b));
 s.data:=jsonb_set(s.data,'{sales}',(s.data->'sales')||jsonb_build_array(sale));
 if not public.mtt_validate(s.data) then raise exception 'MTT_INVALID_DATA'; end if;
 update public.mtt_app_state set data=s.data,revision=s.revision+1,updated_at=now() where id=1;
 insert into public.mtt_change_log(actor,action,revision) values(auth.uid(),'sale',s.revision+1);
 return public.mtt_load();
end $$;
revoke all on function public.mtt_validate(jsonb),public.mtt_load(),public.mtt_save(jsonb,integer),public.mtt_record_sale(jsonb,integer) from public,anon,authenticated;
grant execute on function public.mtt_load(),public.mtt_save(jsonb,integer),public.mtt_record_sale(jsonb,integer) to authenticated;
commit;
