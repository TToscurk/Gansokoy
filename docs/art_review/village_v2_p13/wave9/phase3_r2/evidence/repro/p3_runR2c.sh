#!/bin/bash
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
bash $SC/p3_shots.sh RC p3_at_C.txt p3_free_C.txt
echo SHOT_RC_DONE
bash $SC/p3_final.sh
echo R2C_ALL_DONE
