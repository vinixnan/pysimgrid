# This file is part of pysimgrid, a Python interface to the SimGrid library.
#
# Copyright 2015-2016 Alexey Nazarenko and contributors
#
# This library is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# along with this library.  If not, see <http://www.gnu.org/licenses/>.
#

import itertools
import networkx
import numpy

import cplatform


class PlatformModel(object):
  """
  Platform linear model used for most static scheduling approaches.

  Disregards network topology.
  """
  def __init__(self, simulation):
    hosts = simulation.hosts
    speed = numpy.zeros(len(hosts))
    bandwidth = numpy.zeros((len(hosts), len(hosts)))
    latency = numpy.zeros((len(hosts), len(hosts)))
    for i, src in enumerate(hosts):
      speed[i] = src.speed
      for j in range(i+1, len(hosts)):
        dst = simulation.hosts[j]
        bandwidth[i,j] = bandwidth[j,i] = cplatform.route_bandwidth(src, dst)
        latency[i,j] = latency[j,i] = cplatform.route_latency(src, dst)

    self._speed = speed
    self._bandwidth = bandwidth
    self._latency = latency
    self._mean_speed = speed.mean()
    self._mean_bandwidth = bandwidth.mean() * (bandwidth.size / (bandwidth.size - len(hosts)))
    self._mean_latency = latency.mean() * (latency.size / (bandwidth.size - len(hosts)))
    self._host_map = {host: idx for (idx, host) in enumerate(hosts)}

  @property
  def host_count(self):
    return len(self._speed)

  @property
  def speed(self):
    return self._speed

  @property
  def bandwidth(self):
    return self._bandwidth

  @property
  def latency(self):
    return self._latency

  @property
  def mean_speed(self):
    return self._mean_speed

  @property
  def mean_bandwidth(self):
    return self._mean_bandwidth

  @property
  def mean_latency(self):
    return self._mean_latency

  @property
  def host_map(self):
    return self._host_map

  def eet(self, task, host):
    return task.amount / self._speed[self._host_map[host]]

  def parent_data_ready_time(self, host, parent, dict edge_dict, SchedulerState state):
    cdef dict task_states = state.task_states
    cdef int dst_idx = self._host_map[host]
    cdef int src_idx = self._host_map[task_states[parent]["host"]]
    if src_idx == dst_idx:
      return state.task_states[parent]["ect"]
    return task_states[parent]["ect"] + edge_dict["weight"] / self._bandwidth[src_idx, dst_idx] + self._latency[src_idx, dst_idx]

  def est(self, host, parents, SchedulerState state):
    cdef float result = 0.
    cdef float parent_time
    for parent, edge_dict in parents:
      parent_time = self.parent_data_ready_time(host, parent, edge_dict, state)
      if parent_time > result:
        result = parent_time
    return result

  def host_idx(self, host):
    return self._host_map[host]


cdef class SchedulerState(object):
  cdef dict _task_states
  cdef dict _timetable

  def __init__(self, simulation=None, task_states=None, timetable=None):
    if simulation:
      if task_states or timetable:
        raise Exception("simulation is provided, initial state is not expected")
      self._task_states = {task: {"ect": numpy.nan, "host": None} for task in simulation.tasks}
      self._timetable = {host: [] for host in simulation.hosts}
    else:
      if not task_states or not timetable:
        raise Exception("initial state must be provided")
      self._task_states = task_states
      self._timetable = timetable

  def copy(self):
    # manual copy of initial state
    #   copy.deepcopy is slow as hell
    task_states = {task: dict(state) for (task, state) in self._task_states.items()}
    timetable = {host: list(timesheet) for (host, timesheet) in self._timetable.items()}
    return SchedulerState(task_states=task_states, timetable=timetable)

  @property
  def task_states(self):
    return self._task_states

  @property
  def timetable(self):
    return self._timetable

  @property
  def schedule(self):
    return {host: [task for (task, _, _) in timesheet] for (host, timesheet) in self._timetable.items()}

  def update(self, task, host, int pos, float start, float finish):
    # update task state
    task_state = self._task_states[task]
    task_state["ect"] = finish
    task_state["host"] = host
    # update timesheet
    self._timetable[host].insert(pos, (task, start, finish))


cdef class MinSelector(object):
  cdef object best_key
  cdef object best_value

  def __init__(self):
    self.best_key = None
    self.best_value = None

  def update(self, object key, object value):
    if self.best_key is None or key < self.best_key:
      self.best_key = key
      self.best_value = value

  @property
  def key(self):
    return self.best_key

  @property
  def value(self):
    return self.best_value


def schedulable_order(object nxgraph, dict ranking):
  cdef object state = networkx.DiGraph(nxgraph)
  cdef dict succ = state.succ
  cdef dict pred = state.pred
  sorter = lambda node: (ranking[node], node.name)
  # extract graph root(s)
  ready_nodes = sorted([node for (node, parents) in pred.items() if not parents], key=sorter)
  order = []
  while ready_nodes:
    scheduled = ready_nodes.pop()
    #print(scheduled.name, ranking[scheduled], [t.name for t in nxgraph.pred[scheduled]])
    order.append(scheduled)
    for child in succ[scheduled]:
      child_active_parents = pred[child]
      del child_active_parents[scheduled]
      if not child_active_parents:
        ready_nodes.append(child)
      ready_nodes = sorted(ready_nodes, key=sorter)
  assert len(order) == len(nxgraph)
  return order


def timesheet_insertion(list timesheet, float est, float eet):
  cdef int insert_index = len(timesheet)
  cdef float start_time = timesheet[-1][2] if timesheet else 0
  cdef tuple insertion = (None, 0, 0)
  cdef tuple t1
  cdef tuple t2

  if timesheet:
    for idx in range(len(timesheet)):
      t1 = timesheet[idx - 1] if idx else insertion
      t2 = timesheet[idx]
      slot = t2[1] - max(t1[2], est)
      if slot > eet:
        insert_index = idx
        start_time = t1[2]
        break

  start_time = max(start_time, est)
  return (insert_index, start_time, (start_time + eet))
