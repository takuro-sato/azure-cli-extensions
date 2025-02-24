#!/usr/bin/bash

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 {start|restart|stop} postgresql"
  exit 1
fi

action="$1"
service="$2"

if [ "$service" != "postgresql" ]; then
  echo "Error: Unsupported service '$service'. Only 'postgresql' is supported."
  exit 1
fi

case "$action" in
  start)
    /usr/bin/pg_ctlcluster --skip-systemctl-redirect 14-main start
    exit $?
    ;;
  restart)
    /usr/bin/pg_ctlcluster --skip-systemctl-redirect 14-main stop || true
    /usr/bin/pg_ctlcluster --skip-systemctl-redirect 14-main start
    exit $?
    ;;
  stop)
    /usr/bin/pg_ctlcluster --skip-systemctl-redirect 14-main stop
    exit $?
    ;;
  *)
    echo "Error: Unsupported action '$action'. Use start, restart, or stop."
    exit 1
    ;;
esac
