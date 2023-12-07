#/bin/bash
cd ../
xml="test/data/pl_4hosts.xml"
dot="test/data/basic_graph.dot"
algs="BatchMax BatchMin BatchSufferage DLS DynamicBatchMax DynamicBatchMin DynamicBatchSufferage DynamicMCT HCPT HEFT Lookahead MCT OLB PEFT"
algs="HEFT"
rm -f saida
for alg in $algs
do
    echo $alg >> saida
    python3.6 runalg.py $alg $xml $dot >> saida 2>> err
done