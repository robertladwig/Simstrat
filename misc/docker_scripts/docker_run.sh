#!/bin/bash
if [ $(docker inspect -f '{{.State.Running}}' simstrat) = "false" ]; then
        echo 'simstrat container not running... I wake it up'
        docker start simstrat
fi

docker exec simstrat bash -c "cd /home/Simstrat/; ./run_testcase.sh"