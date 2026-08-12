using './info_cwcow.bicep'

// Image info — the prebuilt confidential-WCOW info-cwcow image lives in
// our ACR (anonymous pull enabled). Left empty so the bicep falls back to
// cacidashboardaci.azurecr.io/prebuilt-test-containers/info-cwcow:latest;
// the workflow param_sets registry/repository/tag. During branch validation
// (before `latest` is published on main) pass a YYYYMMDD tag via the workflow's
// TAG input/default, then flip back to latest at merge.
param registry = ''
param repository = ''
param tag = ''

// Deployment info
param location = 'germanynorth'
param useVnet = false
param addDummyPort = false

// Pre-populated permissive WCOW policy (api_version 0.11.0, mount_cims).
// Matches the wcow_allow_all_policy.rego template emitted by
// `c-aci-testing policies gen ... --policy-type allow_all` for an osType=
// 'Windows' container group. Sufficient for VM-level testing. Re-run
// `c-aci-testing policies gen workloads/info_cwcow --deployment-name <name>`
// only if you need a strict policy bound to the actual layers.
param ccePolicies = {
  info_cwcow: 'cGFja2FnZSBwb2xpY3kKCmFwaV92ZXJzaW9uIDo9ICIwLjExLjAiCgptb3VudF9kZXZpY2UgOj0geyJhbGxvd2VkIjogdHJ1ZX0KbW91bnRfb3ZlcmxheSA6PSB7ImFsbG93ZWQiOiB0cnVlfQpjcmVhdGVfY29udGFpbmVyIDo9IHsiYWxsb3dlZCI6IHRydWUsICJlbnZfbGlzdCI6IG51bGwsICJhbGxvd19zdGRpb19hY2Nlc3MiOiB0cnVlfQptb3VudF9jaW1zIDo9IHsiYWxsb3dlZCI6IHRydWV9CnVubW91bnRfZGV2aWNlIDo9IHsiYWxsb3dlZCI6IHRydWV9CnVubW91bnRfb3ZlcmxheSA6PSB7ImFsbG93ZWQiOiB0cnVlfQpleGVjX2luX2NvbnRhaW5lciA6PSB7ImFsbG93ZWQiOiB0cnVlLCAiZW52X2xpc3QiOiBudWxsfQpleGVjX2V4dGVybmFsIDo9IHsiYWxsb3dlZCI6IHRydWUsICJlbnZfbGlzdCI6IG51bGwsICJhbGxvd19zdGRpb19hY2Nlc3MiOiB0cnVlfQpzaHV0ZG93bl9jb250YWluZXIgOj0geyJhbGxvd2VkIjogdHJ1ZX0Kc2lnbmFsX2NvbnRhaW5lcl9wcm9jZXNzIDo9IHsiYWxsb3dlZCI6IHRydWV9CnBsYW45X21vdW50IDo9IHsiYWxsb3dlZCI6IHRydWV9CnBsYW45X3VubW91bnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0KZ2V0X3Byb3BlcnRpZXMgOj0geyJhbGxvd2VkIjogdHJ1ZX0KZHVtcF9zdGFja3MgOj0geyJhbGxvd2VkIjogdHJ1ZX0KcnVudGltZV9sb2dnaW5nIDo9IHsiYWxsb3dlZCI6IHRydWV9CmxvYWRfZnJhZ21lbnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0Kc2NyYXRjaF9tb3VudCA6PSB7ImFsbG93ZWQiOiB0cnVlfQpzY3JhdGNoX3VubW91bnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0K'
}
