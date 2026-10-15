#!/bin/bash
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
bash $SC/p3_run.sh > $TMPDIR/p3a_run10.out 2>&1
echo RUN10=$? >> $TMPDIR/p3_final.out
bash $TMPDIR/p2_gate.sh > $TMPDIR/p3_gate6.out 2>&1
cat $TMPDIR/p3_gate6.out >> $TMPDIR/p3_final.out
bash $SC/p3_shots.sh A1 p3_at_A.txt p3_free_A.txt
echo SHOT_A1_DONE >> $TMPDIR/p3_final.out
bash $SC/p3_shots.sh C1 p3_at_C.txt p3_free_C.txt
echo SHOT_C1_DONE >> $TMPDIR/p3_final.out
echo FINAL_DONE >> $TMPDIR/p3_final.out
