# -*- coding: utf-8 -*-
# cython: language_level=3

"""Wrapper header of BFGS algorithm.

author: Yuan Chang
copyright: Copyright (C) 2016-2019
license: AGPL
email: pyslvs@gmail.com
"""

from libcpp.list cimport list as clist
from libcpp.vector cimport vector
from libcpp.map cimport map as cmap
from .sketch_solve cimport Point, Line, Constraint


cdef class SolverSystem:

    cdef list vpoints
    cdef dict vlinks
    cdef dict inputs
    cdef dict data_dict

    cdef clist[double] params
    cdef clist[double] constants
    cdef vector[Point] points
    cdef cmap[int, int] sliders
    cdef vector[Point] slider_bases
    cdef vector[Point] slider_slots
    cdef clist[Line] slider_lines

    cdef clist[Constraint] cons_list
    cdef clist[Line] handles
    cdef vector[double] inputs_angle

    cdef void build_expression(self)
    cpdef void set_inputs(self, dict inputs)
    cpdef list solve(self)
