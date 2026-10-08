import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, copyFileSync, readFileSync, rmSync, chmodSync, statSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {execFileSync, spawnSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {scanRepository, loadPolicy} from './scan.mjs';

const project=resolve(import.meta.dirname,'../..');
const git=(root,args)=>execFileSync('git',args,{cwd:root,stdio:'pipe'});
function fixture(t) {
  const root=mkdtempSync(join(tmpdir(),'secret-canary-'));t.after(()=>rmSync(root,{recursive:true,force:true}));
  const secret=`fixture-${randomUUID().replaceAll('-','')}`;
  mkdirSync(join(root,'.local/tools'),{recursive:true});mkdirSync(join(root,'tools/security'),{recursive:true});
  copyFileSync(join(project,'.local/tools/gitleaks'),join(root,'.local/tools/gitleaks'));chmodSync(join(root,'.local/tools/gitleaks'),0o700);
  copyFileSync(join(project,'tools/security/gitleaks-lock.json'),join(root,'tools/security/gitleaks-lock.json'));
  copyFileSync(join(project,'.gitleaks.toml'),join(root,'.gitleaks.toml'));
  const policy={version:1,forbiddenValues:[secret],allowedBinaryPrefixes:[]};
  writeFileSync(join(root,'.local/security-policy.json'),JSON.stringify(policy));
  writeFileSync(join(root,'.gitignore'),'.local/\noutput/\n.env\n');
  writeFileSync(join(root,'safe.txt'),'safe fixture\n');
  git(root,['init','-b','main']);git(root,['config','user.name','Migration Test']);git(root,['config','user.email','migration@example.invalid']);
  git(root,['add','safe.txt','.gitignore','.gitleaks.toml','tools/security/gitleaks-lock.json']);git(root,['commit','-m','safe baseline']);
  return {root,secret,policy};
}
test('S01 안전한 파일은 검사하고 인증 링크와 금지 값을 검출한다',t=>{
  const {root,secret}=fixture(t);assert.equal(scanRepository({root}).verdict,'passed');
  writeFileSync(join(root,'action.txt'),`https://example.invalid/?oobCode=${secret}\n`);
  const result=scanRepository({root});assert.equal(result.verdict,'failed');
  assert.ok(result.findings.some(f=>f.rule==='outpick-auth-link'));
});
test('S02 작업트리에서 지운 값도 index 전체 검사에서 검출한다',t=>{
  const {root,secret}=fixture(t);writeFileSync(join(root,'staged.txt'),secret);git(root,['add','staged.txt']);
  writeFileSync(join(root,'staged.txt'),'safe now');
  assert.equal(scanRepository({root,mode:'candidate'}).verdict,'passed');
  assert.equal(scanRepository({root,mode:'index'}).verdict,'failed');
  writeFileSync(join(root,'.env'),'fake setting');git(root,['add','--force','.env']);
  assert.ok(scanRepository({root,mode:'index'}).findings.some(f=>f.rule==='forbidden-path'));
});
test('S03 현재 삭제된 비밀도 이전 전송 commit에서 검출한다',t=>{
  const {root,secret}=fixture(t);writeFileSync(join(root,'past.txt'),secret);git(root,['add','past.txt']);git(root,['commit','-m','canary history']);
  git(root,['rm','past.txt']);git(root,['commit','-m','remove canary']);
  assert.equal(scanRepository({root,mode:'history',ref:'HEAD'}).verdict,'failed');
  assert.throws(()=>scanRepository({root,mode:'history',ref:'--all'}),/INVALID_HISTORY_REF/);
});
test('S04 미준비 도구와 정책 및 runner 오류는 차단한다',t=>{
  const {root}=fixture(t);assert.throws(()=>scanRepository({root,run:()=>({status:2,stdout:'',stderr:''})}),/SCANNER_EXECUTION_ERROR/);
  rmSync(join(root,'.local/tools/gitleaks'));assert.throws(()=>scanRepository({root}),/SCANNER_CHECKSUM/);
  rmSync(join(root,'.local/security-policy.json'));assert.throws(()=>loadPolicy(root),/LOCAL_POLICY_REQUIRED/);
});
test('S05 로그와 결과에 비밀 원문을 남기지 않고 실패와 0600을 보존한다',t=>{
  const {root,secret}=fixture(t);writeFileSync(join(root,'action.txt'),`https://example.invalid/?oobCode=${secret}`);
  const result=scanRepository({root,run:(binary,args,options)=>{
    const raw=spawnSync(binary,args,options);
    assert.equal(`${raw.stdout}${raw.stderr}`.includes(secret),false);
    const path=args[args.indexOf('--report-path')+1];assert.equal(readFileSync(path,'utf8').includes(secret),false);
    return raw;
  }});
  assert.equal(result.verdict,'failed');assert.equal(JSON.stringify(result).includes(secret),false);
  assert.equal(readFileSync(result.report,'utf8').includes(secret),false);assert.equal(statSync(result.report).mode&0o777,0o600);
});
test('S06 symlink 미분류 binary와 넓은 예외 정책을 거부한다',t=>{
  const {root,policy}=fixture(t);symlinkSync(join(root,'safe.txt'),join(root,'linked.txt'));
  assert.throws(()=>scanRepository({root}),/NONREGULAR/);rmSync(join(root,'linked.txt'));
  writeFileSync(join(root,'unknown.bin'),Buffer.from([0,1,2]));assert.throws(()=>scanRepository({root}),/UNREVIEWED_BINARY/);
  writeFileSync(join(root,'.local/security-policy.json'),JSON.stringify({...policy,allowedBinaryPrefixes:['tests/']}));
  assert.throws(()=>loadPolicy(root),/INVALID_LOCAL_POLICY/);
});
