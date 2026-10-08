import {readdirSync, statSync} from 'node:fs';
import {resolve, join} from 'node:path';
import {spawnSync} from 'node:child_process';

const reporter=process.env.OUTPICK_GATE_REPORTER_PATH,destination=process.env.OUTPICK_GATE_RESULT_PATH;
if(Boolean(reporter)!==Boolean(destination))throw new Error('reporter와 결과 경로를 함께 지정해야 합니다.');
const directories=process.argv.slice(2);if(!directories.length)throw new Error('테스트 경로가 필요합니다.');
const walk=directory=>statSync(directory).isFile()?[directory]:readdirSync(directory,{withFileTypes:true}).flatMap(entry=>entry.isDirectory()?walk(join(directory,entry.name)):[join(directory,entry.name)]);
const files=directories.flatMap(directory=>walk(resolve(directory))).filter(file=>/\.test\.(?:mjs|cjs|js)$/.test(file)).sort();
if(!files.length)throw new Error('실행할 Node 테스트가 없습니다.');
const args=['--test','--test-concurrency=1',...(reporter?['--test-reporter',reporter,'--test-reporter-destination',destination]:[]),...files];
const result=spawnSync(process.execPath,args,{stdio:'inherit'});if(result.error)throw result.error;process.exitCode=result.status??1;
