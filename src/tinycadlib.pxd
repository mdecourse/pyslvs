# -*- coding: utf-8 -*-
# cython: language_level=3

"""Sharing position analysis function.

author: Yuan Chang
copyright: Copyright (C) 2016-2018
license: AGPL
email: pyslvs@gmail.com
"""

from cpython cimport bool


cdef class Coordinate:
    cdef readonly double x, y

    cpdef double distance(self, Coordinate p)
    cpdef bool is_nan(self)


cdef double radians(double degree)
cpdef tuple PLAP(Coordinate A, double L0, double a0, Coordinate B = *, bool inverse = *)
cpdef tuple PLLP(Coordinate A, double L0, double L1, Coordinate B, bool inverse = *)
cpdef tuple PLPP(Coordinate A, double L0, Coordinate B, Coordinate C, bool inverse = *)
cpdef tuple PXY(Coordinate A, double x, double y)

cdef bool legal_crank(Coordinate A, Coordinate B, Coordinate C, Coordinate D)
cdef str str_between(str s, str front, str back)
cdef str str_before(str s, str front)
