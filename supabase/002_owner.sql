-- Run only after creating the intended owner in Supabase Authentication.
-- This does not create or reset a password, and never assigns owner via client signup.
do $$
declare u uuid; owner_email text := 'REPLACE_WITH_OWNER_EMAIL';
begin
 if owner_email = 'REPLACE_WITH_OWNER_EMAIL' then raise exception 'Set owner_email before running this script'; end if;
 select id into u from auth.users where lower(email)=lower(owner_email);
 if u is null then raise exception 'Create the owner Auth user first'; end if;
 insert into public.mtt_profiles(user_id,full_name,phone,role,approved)
 values(u,'Quản trị','','owner',true)
 on conflict(user_id) do update set role='owner',approved=true;
end $$;
