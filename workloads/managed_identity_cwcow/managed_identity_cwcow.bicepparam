using './managed_identity_cwcow.bicep'

// Image info — tag retained for c-aci-testing parameter parity; left empty so
// the bicep template pins the servercore image by digest (see its inline
// comment for why a tag ref breaks the VM harness's manifest resolution).
param tag=''

// Deployment info
param location='westeurope'
param useVnet=false

// Pre-populated allow-all policy (same permissive policy used by the other
// _cwcow workloads). CI deploys with --policy-type allow_all, which regenerates
// this; the literal here keeps a standalone `az deployment` working too.
param ccePolicies={
  managed_identity_cwcow: 'cGFja2FnZSBwb2xpY3kKCmFwaV92ZXJzaW9uIDo9ICIwLjExLjAiCgptb3VudF9kZXZpY2UgOj0geyJhbGxvd2VkIjogdHJ1ZX0KbW91bnRfb3ZlcmxheSA6PSB7ImFsbG93ZWQiOiB0cnVlfQpjcmVhdGVfY29udGFpbmVyIDo9IHsiYWxsb3dlZCI6IHRydWUsICJlbnZfbGlzdCI6IG51bGwsICJhbGxvd19zdGRpb19hY2Nlc3MiOiB0cnVlfQptb3VudF9jaW1zIDo9IHsiYWxsb3dlZCI6IHRydWV9CnVubW91bnRfZGV2aWNlIDo9IHsiYWxsb3dlZCI6IHRydWV9CnVubW91bnRfb3ZlcmxheSA6PSB7ImFsbG93ZWQiOiB0cnVlfQpleGVjX2luX2NvbnRhaW5lciA6PSB7ImFsbG93ZWQiOiB0cnVlLCAiZW52X2xpc3QiOiBudWxsfQpleGVjX2V4dGVybmFsIDo9IHsiYWxsb3dlZCI6IHRydWUsICJlbnZfbGlzdCI6IG51bGwsICJhbGxvd19zdGRpb19hY2Nlc3MiOiB0cnVlfQpzaHV0ZG93bl9jb250YWluZXIgOj0geyJhbGxvd2VkIjogdHJ1ZX0Kc2lnbmFsX2NvbnRhaW5lcl9wcm9jZXNzIDo9IHsiYWxsb3dlZCI6IHRydWV9CnBsYW45X21vdW50IDo9IHsiYWxsb3dlZCI6IHRydWV9CnBsYW45X3VubW91bnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0KZ2V0X3Byb3BlcnRpZXMgOj0geyJhbGxvd2VkIjogdHJ1ZX0KZHVtcF9zdGFja3MgOj0geyJhbGxvd2VkIjogdHJ1ZX0KcnVudGltZV9sb2dnaW5nIDo9IHsiYWxsb3dlZCI6IHRydWV9CmxvYWRfZnJhZ21lbnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0Kc2NyYXRjaF9tb3VudCA6PSB7ImFsbG93ZWQiOiB0cnVlfQpzY3JhdGNoX3VubW91bnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0K'
}

// Overridden at deploy time by aci_deploy from $MANAGED_IDENTITY (the param must
// already exist here for aci_param_set's add=False replace to take effect).
param managedIDName='cacidashboard'
