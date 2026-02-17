#!/usr/bin/env node
// Security gate: fail if npm audit reports high or critical vulnerabilities.
// Called during docker build to prevent vulnerable images from being deployed.
let raw = '';
process.stdin.on('data', d => { raw += d; });
process.stdin.on('end', () => {
  let report;
  try { report = JSON.parse(raw); } catch (e) {
    console.error('WARN: Could not parse npm audit output — skipping gate');
    process.exit(0);
  }
  const v = report.metadata && report.metadata.vulnerabilities || {};
  const bad = (v.high || 0) + (v.critical || 0);
  if (bad > 0) {
    console.error('SECURITY GATE FAILED: ' + bad + ' high/critical vulnerability(ies) in openclaw dependencies.');
    console.error('Vulnerability summary: ' + JSON.stringify(v, null, 2));
    console.error('Run `npm audit --prefix /usr/lib/node_modules/openclaw` for details.');
    console.error('Do NOT deploy this image. See UPGRADE.md for guidance.');
    process.exit(1);
  }
  console.log('Security gate passed. Vulnerability summary: ' + JSON.stringify(v));
});
