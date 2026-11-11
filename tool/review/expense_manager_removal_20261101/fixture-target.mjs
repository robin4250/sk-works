export const blockedEnvironment = Object.freeze([
  'DATABASE_URL','SUPABASE_DB_URL','PGHOST','PGHOSTADDR','PGPORT','PGDATABASE',
  'PGUSER','PGPASSWORD','PGSERVICE','PGSERVICEFILE','PGOPTIONS','PGSSLMODE',
  'SKO_EXPENSE_MANAGER_REMOVAL_DATABASE_URL','SKO_EXPENSE_REVIEW_DATABASE_URL',
]);
export function fixtureTarget(env = process.env) {
  for (const name of blockedEnvironment) {
    if (env[name]) throw new Error('External database configuration is not allowed in this fixture');
  }
  return Object.freeze({host:'127.0.0.1',port:55438,user:'postgres',password:'fixture-only',
    database:'sko_expense_manager_removal_fixture',ssl:false,application_name:'sko-expense-removal-isolated'});
}
