# EPM_SaaS_API
CyberArk EPM SaaS JIT Policy Creation via API

# Overview
This repository of downloadable REST API example scripts show users how to automate key processes across their EPM SaaS implementation, including how to create and update policies, collecting Inbox events and audit logs.

Please note These scripts were made available as examples to show administrators how to use CyberArk REST APIs for EPM SaaS. They are not as a supported product of CyberArk.

# Pre-Requisites
- EPM SaaS Tenant Access
- Username and Password to authenticate to EPM SaaS with appropriate permissions for the actions

# Scripts
EPM_SaaS_REST-API_Create-JIT-Policy-From-Manual-Request_TimeInRequest.ps1
  > Expects the Time Frame in the Manual Request
  > Manual Request must end with e.g. "...time=6"
  > No validation check if valid time is a valid number
  > Validation check if Active Policy exists for single Username & single Computername combination
  > Delete mulitple requests and just create one JIT policy for single Username & single Computername combination
EPM_SaaS_REST-API_Create-JIT-Policy-From-Manual-Request_FixedTime.ps1
- C
- D
