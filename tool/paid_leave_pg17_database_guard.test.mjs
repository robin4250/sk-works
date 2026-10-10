import test from 'node:test';
import assert from 'node:assert/strict';
import {validatePaidLeaveFixtureUrl as validate} from './paid_leave_pg17_database_guard.mjs';
test('only known local disposable database is accepted',()=>{
  for (const host of ['localhost','127.0.0.1','[::1]'])
    assert.match(validate(`postgres://postgres:fixture-only-password@${host}:5432/sko_paid_leave_fixture`),/sko_paid_leave_fixture$/);
});
test('remote, query overrides, sockets, arbitrary databases and credentials fail before connect',()=>{
  for (const value of [undefined,'not-a-url',
    'postgres://postgres:fixture-only-password@db.example.com:5432/sko_paid_leave_fixture',
    'postgres://postgres:fixture-only-password@127.0.0.1:5432/postgres',
    'postgres://postgres:fixture-only-password@127.0.0.1:5432/sko_paid_leave_fixture?host=db.example.com',
    'postgres://postgres:fixture-only-password@127.0.0.1:5432/sko_paid_leave_fixture?host=/var/run/postgresql',
    'postgres://postgres:real-password@localhost:5432/sko_paid_leave_fixture',
    'postgres://postgres:fixture-only-password@localhost:6543/sko_paid_leave_fixture',
    'https://postgres:fixture-only-password@localhost:5432/sko_paid_leave_fixture'])
    assert.throws(()=>validate(value),/Only the local disposable/);
});
