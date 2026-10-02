revoke execute on function public.company_data_state() from anon;
revoke execute on function public.daily_report_clocked_in_destinations(date) from anon;
revoke execute on function public.my_attendance_allowance_units() from anon;
revoke execute on function public.save_company_allowance_units(text,text,text) from anon;
revoke execute on function public.save_company_data(text,text,text,text,text,text,text,text,text,text) from anon;
revoke execute on function public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb) from anon;

grant execute on function public.company_data_state() to authenticated;
grant execute on function public.daily_report_clocked_in_destinations(date) to authenticated;
grant execute on function public.my_attendance_allowance_units() to authenticated;
grant execute on function public.save_company_allowance_units(text,text,text) to authenticated;
grant execute on function public.save_company_data(text,text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.save_daily_report_destination_draft(uuid,uuid,uuid,date,text,jsonb) to authenticated;
