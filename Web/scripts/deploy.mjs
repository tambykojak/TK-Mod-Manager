// Uploads Web/dist to the bucket from Web/infra and clears the CloudFront cache.
// Run after terraform apply. npm run deploy builds first.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const infra = resolve(siteRoot, "infra");
const dist = resolve(siteRoot, "dist");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.error) {
    console.error(`failed to run ${command}: ${result.error.message}`);
    process.exit(1);
  }
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function terraformOutput(name) {
  const result = spawnSync("terraform", ["output", "-raw", name], {
    cwd: infra,
    encoding: "utf8",
  });
  if (result.error) {
    console.error(`failed to run terraform: ${result.error.message}`);
    process.exit(1);
  }
  if (result.status !== 0) {
    if (result.stderr) process.stderr.write(result.stderr);
    console.error("terraform output failed. Apply Web/infra first.");
    process.exit(result.status ?? 1);
  }
  return result.stdout.trim();
}

function savedDeploy() {
  const savedPath = resolve(infra, "deploy.json");
  if (!existsSync(savedPath)) return null;
  return JSON.parse(readFileSync(savedPath, "utf8"));
}

const saved = savedDeploy();
const bucket = saved?.bucket ?? terraformOutput("bucket_name");
const distributionId = saved?.distributionId ?? terraformOutput("distribution_id");
const url = saved?.url ?? terraformOutput("url");

if (!bucket || !distributionId) {
  console.error("terraform output was empty. Apply Web/infra first.");
  process.exit(1);
}

run("aws", ["s3", "sync", dist, `s3://${bucket}`, "--delete"]);
run("aws", [
  "cloudfront",
  "create-invalidation",
  "--distribution-id",
  distributionId,
  "--paths",
  "/*",
]);

console.log(url);
