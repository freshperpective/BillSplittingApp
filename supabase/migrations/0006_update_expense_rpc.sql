-------------------------------------------------------------------------------
-- Atomic expense edit (row + shares replacement).
--
-- The validate_expense_shares constraint trigger from 0001 is DEFERRABLE
-- INITIALLY DEFERRED, which means inside a single transaction we can
-- delete every share row, update the expense amount, and insert new shares
-- — the check only runs at commit and sees the final, consistent state.
--
-- PostgREST runs each HTTP request as its own transaction, so we can't
-- bundle that from the client. A SECURITY DEFINER RPC bundles it into one
-- function call = one transaction. The function explicitly checks that the
-- caller is the expense creator (mirrors the UPDATE policy from 0001) so we
-- don't lose authorization by going through the definer.
-------------------------------------------------------------------------------
create or replace function public.update_expense_with_shares(
  p_expense_id   uuid,
  p_description  text,
  p_amount       numeric,
  p_currency     text,
  p_fx_to_group  numeric,
  p_paid_at      date,
  p_category     text,
  p_note         text,
  p_shares       jsonb  -- [{profile_id, paid_share, owed_share}, ...]
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_creator uuid;
begin
  if v_uid is null then
    raise insufficient_privilege using message = 'Not signed in';
  end if;

  select created_by into v_creator from public.expenses where id = p_expense_id;
  if v_creator is null then
    raise exception 'Expense % not found', p_expense_id using errcode = 'P0002';
  end if;
  if v_creator <> v_uid then
    raise insufficient_privilege using message = 'Only the creator can edit this expense';
  end if;

  update public.expenses set
    description = p_description,
    amount      = p_amount,
    currency    = p_currency,
    fx_to_group = p_fx_to_group,
    paid_at     = p_paid_at,
    category    = p_category,
    note        = p_note
  where id = p_expense_id;

  -- Replace shares. The trigger is deferred, so the interim "no shares"
  -- state doesn't blow up — only the final commit gets validated.
  delete from public.expense_shares where expense_id = p_expense_id;

  insert into public.expense_shares (expense_id, profile_id, paid_share, owed_share)
  select
    p_expense_id,
    (s->>'profile_id')::uuid,
    (s->>'paid_share')::numeric,
    (s->>'owed_share')::numeric
  from jsonb_array_elements(p_shares) as s;
end
$$;

revoke execute on function public.update_expense_with_shares(uuid, text, numeric, text, numeric, date, text, text, jsonb) from public;
grant  execute on function public.update_expense_with_shares(uuid, text, numeric, text, numeric, date, text, text, jsonb) to authenticated;
