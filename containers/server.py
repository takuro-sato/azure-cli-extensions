#!/usr/bin/env python3

"""
A persistant python3 server to respond to our curl checks, report uptime, and
extract dmesg without needing policy alterations.
"""

from fastapi import FastAPI, Response, HTTPException
from fastapi.responses import PlainTextResponse
from subprocess import check_output, STDOUT, CalledProcessError
from os import getenv
from datetime import datetime, timezone


def checked_exec_get_output(cmd: str) -> bytes:
    return check_output(cmd, shell=True, stderr=STDOUT)


startup_time = datetime.now(timezone.utc)
startup_str = (
    f"Server started at {startup_time.isoformat()}\n\n"
    + f"uptime:\n{checked_exec_get_output('uptime').decode('utf-8')}\n"
    + f"uname -a:\n{checked_exec_get_output('uname -a').decode('utf-8')}\n"
)
req_count = 0

app = FastAPI()


@app.get('/', response_class=PlainTextResponse)
@app.get('/index.txt', response_class=PlainTextResponse)
async def index():
    global req_count
    req_received_at = datetime.now(timezone.utc)
    req_count += 1

    response_text = "Hello from container!\n"
    response_text += startup_str
    response_text += f"Request received at {req_received_at.isoformat()} "
    delta = req_received_at - startup_time
    response_text += f"which is {delta.total_seconds()}s after startup.\n"
    response_text += f"Request to / received including this one: {req_count}.\n"

    return response_text


@app.get('/dmesg.log')
async def dmesg():
    try:
        output = checked_exec_get_output("dmesg")
        return Response(content=output, media_type='text/plain')
    except CalledProcessError as e:
        return Response(content=e.output, status_code=500, media_type='text/plain')


@app.exception_handler(404)
async def not_found(request, exc):
    return PlainTextResponse(content="Not Found\n", status_code=404)


if __name__ == '__main__':
    PORT = int(getenv("PORT", "80"))
    print(f"Listening on port {PORT}", flush=True)
    print(startup_str, flush=True)

    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
