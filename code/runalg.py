from pysimgrid import simdag
import pysimgrid.simdag.algorithms as algorithms
import networkx
import sys


def run_simulation(alg, xml, dot):
    with simdag.Simulation(xml, dot) as simulation:
      classdef = getattr(algorithms, alg)
      scheduler = classdef(simulation)
      scheduler.run()
      print(simulation.clock, scheduler.scheduler_time, scheduler.total_time)
      print(dir(scheduler.state))

      print(scheduler.state.max_time)
      print(scheduler.state.schedule)
      print(scheduler.state.task_states)
      print(scheduler.state.timetable)
      print(scheduler.state.update)



alg = sys.argv[1]
xml = sys.argv[2]
dot = sys.argv[3]

run_simulation(alg, xml, dot)