#!/usr/bin/python
import click
from pysimgrid import simdag
import pysimgrid.simdag.algorithms as algorithms
import networkx
import sys

import collections

collections.Mapping = collections.abc.Mapping

collections.Sequence = collections.abc.Sequence

algs=['BatchMax',
 'BatchMin',
 'BatchSufferage',
 'DLS',
 'DynamicBatchMax',
 'DynamicBatchMin',
 'DynamicBatchSufferage',
 'DynamicMCT',
 'HCPT',
 'HEFT',
 'Lookahead',
 'MCT',
 'OLB',
 'PEFT',
 'RandomStatic',
 'RoundRobinStatic',
 'SimHEFT',]


@click.command()
@click.option(
    "--conf", help="Path for a XML File containing the host configuration", required=True
)
@click.option(
    "--problem",
    "-p",
    help="Path for the problem definition (.dot file)",
    required=True,
)
@click.option(
    "--alg", "-a", help="Algorithm in "+str(algs), default=["HEFT"]
)
def run(
    conf,
    problem,
    alg,
):
    with simdag.Simulation(conf, problem) as simulation:
      classdef = getattr(algorithms, alg)
      scheduler = classdef(simulation)
      scheduler.run()
      print(simulation.clock, scheduler.scheduler_time, scheduler.total_time)
    


if __name__ == "__main__":
    run()






