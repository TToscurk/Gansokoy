#!/bin/bash
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
bash $SC/p3_shots.sh Cid2on p3_at_cid4.txt - --id
bash $SC/p3_shots.sh Cid2off p3_at_cid4.txt - --id --disable=EnrichW9P3
echo IDRUN_DONE
