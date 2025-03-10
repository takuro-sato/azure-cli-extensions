## Stress tests

These tests are designed to provoke certain kernel issues we've seen in the past. Aside from checking that container is alive etc we also want to check that warning / BUG / segfault / GP messages does not show up in dmesg. This is done in [.github/workflows/workload-stress-tests.yml](../../.github/workflows/workload-stress-tests.yml).

The stress testers are given nice +10 so that it doesn't starve the Python server of CPU, causing checks to fail.

(Doing it the other way -- giving python nice -10 -- would be better, but we get permission errors on unprivileged containers)
