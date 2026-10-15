#!/bin/bash
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
bash $SC/p3_shots.sh RB p3_at_B.txt p3_free_B.txt
echo SHOT_RB_DONE
bash $SC/p3_shots.sh RA p3_at_A.txt p3_free_A.txt
echo SHOT_RA_DONE
echo R2B_SHOTS_DONE
