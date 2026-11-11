#!/bin/sh
exec /usr/bin/python3 -I -S "$(/usr/bin/dirname "$0")/offline_docker_generator.py" "$@"
