## Stress tests

These tests are designed to provoke certain kernel issues we've seen in the past. Aside from checking that container is alive etc we also want to check that warning / BUG / segfault / GP messages does not show up in dmesg. This is done in [.github/workflows/workload-stress-tests.yml](../../.github/workflows/workload-stress-tests.yml).
