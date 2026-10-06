-- Force existing automatic draft payroll statements through the custom-deduction guard.
update public.payroll_statements
set deductions=deductions
where automatic_calculation
  and workflow_state='draft';
