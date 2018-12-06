# -*- coding: utf-8 -*-
# cython: language_level=3

"""Layout functions for graph object.

The algorithms references:
+ NetworkX

author: Yuan Chang
copyright: Copyright (C) 2016-2018
license: AGPL
email: pyslvs@gmail.com
"""

from collections.abc import Set, Iterable
from cpython cimport PyDict_Contains, PyIndex_Check
from cpython.slice cimport PySlice_GetIndicesEx
from libc.math cimport M_PI, sin, cos
from graph cimport Graph


cpdef dict outer_loop_layout(Graph g, bint node_mode, double scale = 1.):
    """Layout position decided by outer loop."""
    cdef OrderedSet o_loop = outer_loop(g)
    cdef list outer_pos = regular_polygon_pos(len(o_loop))

    # Match the outer loop.
    cdef dict pos = dict(zip(o_loop, outer_pos))

    # Find other connections from edges.
    cdef OrderedSet line = OrderedSet([])
    cdef OrderedSet nodes = set(g.nodes) - o_loop
    cdef OrderedSet used_nodes = o_loop.copy()

    # Layout for inner nodes of graph block.
    cdef int n, start, end
    cdef OrderedSet neighbors, new_neighbors, intersection
    while nodes:
        n = nodes.pop(0)
        neighbors = OrderedSet(g.adj[n])
        intersection = neighbors & (used_nodes | line)
        if not intersection:
            # Not contacted yet.
            nodes.add(n)
            continue

        line.add(n)
        new_neighbors = neighbors - intersection
        if new_neighbors:
            # New nodes to add.
            line.add(new_neighbors.pop())
        else:
            # Line is ended.
            intersection = line & o_loop
            start = intersection.pop()
            end = intersection.pop()
            pos.update(zip(line, linear_layout(pos[start], pos[end], len(line))))
            used_nodes.update(line)
            line.clear()

        nodes.remove(n)

    # TODO: node_mode

    return pos


cdef list regular_polygon_pos(int edge_count):
    """Return position of a regular polygon with radius 10.
    Start from bottom with clockwise.
    """
    cdef int i
    cdef double angle = M_PI * 3 / 2
    cdef double angle_step = 2 * M_PI / edge_count
    cdef list pos = []
    for i in range(edge_count):
        pos.append((10 * cos(angle), 10 * sin(angle)))
        angle -= angle_step
    return pos


cdef list linear_layout(tuple c0, tuple c1, int count):
    """Layout position decided by equal division between two points."""
    if count < 1:
        raise ValueError(f"Invalid point number {count}")

    count += 1
    cdef double sx = (c1[0] - c0[0]) / count
    cdef double sy = (c1[1] - c0[1]) / count
    cdef int i
    return [(c0[0] + i * sx, c0[1] + i * sy) for i in range(1, count)]


cdef OrderedSet outer_loop(Graph graph):
    """Return nodes of outer loop."""
    cdef OrderedSet c1, c2, c3
    cdef list cycles = cycle_basis(graph)
    while len(cycles) > 1:
        c1 = cycles.pop()

        for c2 in cycles:
            c3 = c1 & c2
            if len(c3) >= 2:
                if c1.isorderedsuperset(c3) == c2.isorderedsuperset(c3):
                    # Cycle 1 and cycle 2 has same direction.
                    c2.reverse()
                break
        else:
            # No contacted.
            raise ValueError("Invalid graph")

        cycles.remove(c2)
        cycles.append(c1 | c2)

    return cycles.pop()


cdef inline list cycle_basis(Graph graph):
    """ Returns a list of cycles which form a basis for cycles of G."""
    cdef set g_nodes = set(graph.nodes)
    cdef list cycles = []
    cdef int root = -1

    cdef int z, nbr, p
    cdef list stack
    cdef set zused, pn
    cdef OrderedSet cycle
    cdef dict pred, used
    while g_nodes:
        # loop over connected components
        if root == -1:
            root = g_nodes.pop()
        stack = [root]
        pred = {root: root}
        used = {root: set()}
        # walk the spanning tree finding cycles
        while stack:
            # use last-in so cycles easier to find
            z = stack.pop()
            zused = used[z]
            for nbr in graph.adj[z]:
                if nbr not in used:
                    # new node
                    pred[nbr] = z
                    stack.append(nbr)
                    used[nbr] = {z}
                elif nbr == z:
                    # self loops
                    cycles.append([z])
                elif nbr not in zused:
                    # found a cycle
                    pn = used[nbr]
                    cycle = OrderedSet([nbr, z])
                    p = pred[z]
                    while p not in pn:
                        cycle.add(p)
                        p = pred[p]
                    cycle.add(p)
                    cycles.append(cycle)
                    used[nbr].add(z)
        g_nodes -= set(pred)
        root = -1
    return cycles


cdef class Entry:
    cdef object key
    cdef Entry prev
    cdef Entry next


cdef inline void _add(OrderedSet oset, object key):
    cdef Entry end = oset.end
    cdef dict map = oset.map
    cdef Entry next

    if not PyDict_Contains(map, key):
        next = Entry()
        next.key, next.prev, next.next = key, end.prev, end
        end.prev.next = end.prev = map[key] = next
        oset.os_used += 1


cdef void _discard(OrderedSet oset, object key):
    cdef dict map = oset.map
    cdef Entry entry

    if PyDict_Contains(map, key):
        entry = map.pop(key)
        entry.prev.next = entry.next
        entry.next.prev = entry.prev
        oset.os_used -= 1


cdef inline bint _isorderedsubset(seq1, seq2):
    if not len(seq1) <= len(seq2):
            return False
    for self_elem, other_elem in zip(seq1, seq2):
        if self_elem != other_elem:
            return False
    return True


cdef class OrderedSetIterator:

    """Ordered set iterator."""

    cdef OrderedSet oset
    cdef Entry curr
    cdef ssize_t si_used

    def __cinit__(self, OrderedSet oset):
        self.oset = oset
        self.curr = oset.end
        self.si_used = oset.os_used

    def __iter__(self):
        return self

    def __next__(self):
        cdef Entry item

        if self.si_used != self.oset.os_used:
            # make this state sticky
            self.si_used = -1
            raise RuntimeError(f'{type(self.oset).__name__} changed size during iteration')

        item = self.curr.next
        if item == self.oset.end:
            raise StopIteration()
        self.curr = item
        return item.key


cdef class OrderedSetReverseIterator:

    """Ordered set iterator with reversed order."""

    cdef OrderedSet oset
    cdef Entry curr
    cdef ssize_t si_used

    def __cinit__(self, OrderedSet oset):
        self.oset = oset
        self.curr = oset.end
        self.si_used = oset.os_used

    def __iter__(self):
        return self

    def __next__(self):
        if self.si_used != self.oset.os_used:
            # make this state sticky
            self.si_used = -1
            raise RuntimeError(f'{type(self.oset).__name__} changed size during iteration')

        cdef Entry item = self.curr.prev
        if item is self.oset.end:
            raise StopIteration()
        self.curr = item
        return item.key


cdef class OrderedSet:

    """Ordered set container."""

    cdef dict map
    cdef Entry end
    cdef ssize_t os_used

    def __cinit__(self):
        self.map = {}
        self.os_used = 0
        self.end = end = Entry()
        end.prev = end.next = end

    def __init__(self, object iterable=None):
        if iterable is None:
            return

        cdef Entry next_e
        cdef dict map_d = self.map
        cdef Entry end = self.end
        for elem in iterable:
            if not PyDict_Contains(map_d, elem):
                next_e = Entry()
                next_e.key, next_e.prev, next_e.next = elem, end.prev, end
                end.prev.next = end.prev = map_d[elem] = next_e
                self.os_used += 1

    @classmethod
    def _from_iterable(cls, it):
        return cls(it)

    ##
    # set methods
    ##
    cpdef void add(self, elem):
        """Add element `elem` to the set."""
        _add(self, elem)

    cpdef void discard(self, elem):
        """Remove element `elem` from the ``OrderedSet`` if it is present."""
        _discard(self, elem)

    cpdef object pop(self, int index = -1):
        """Remove and return the last element or an arbitrary set element.
        Raises ``KeyError`` if the ``OrderedSet`` is empty.
        """
        if not self:
            raise KeyError(f'{self.__class__.__name__} is empty')
        key = self[index]
        _discard(self, key)
        return key

    cpdef void remove(self, elem):
        """
        Remove element `elem` from the ``set``.
        Raises :class:`KeyError` if `elem` is not contained in the set.
        """
        if elem not in self:
            raise KeyError(elem)
        _discard(self, elem)

    cpdef void clear(self):
        """Remove all elements from the `set`."""
        cdef Entry end = self.end
        end.next.prev = end.next = None

        # reinitialize
        self.map.clear()
        self.os_used = 0
        self.end = end = Entry()
        end.prev = end.next = end

    cpdef OrderedSet copy(self):
        """Copy the instance."""
        return self._from_iterable(self)

    def __sub__(self, other) -> OrderedSet:
        """Implement of '-' operator."""
        ostyp = type(self if isinstance(self, OrderedSet) else other)

        if not isinstance(self, Iterable):
            return NotImplemented
        if not isinstance(other, Set):
            if not isinstance(other, Iterable):
                return NotImplemented
            other = ostyp._from_iterable(other)

        return ostyp._from_iterable(value for value in self if value not in other)

    def __isub__(self, other) -> OrderedSet:
        """Implement of '-=' operator."""
        if other is self:
            self.clear()
        else:
            for value in other:
                self.discard(value)
        return self

    cpdef OrderedSet intersection(self, other):
        """Method of '&' operator."""
        return self & other

    def __and__(self, other) -> OrderedSet:
        """Implement of '&' operator."""
        ostyp = type(self if isinstance(self, OrderedSet) else other)

        if not isinstance(self, Iterable):
            return NotImplemented
        if not isinstance(other, Set):
            if not isinstance(other, Iterable):
                return NotImplemented
            other = ostyp._from_iterable(other)

        return ostyp._from_iterable(value for value in self if value in other)

    def __iand__(self, it):
        """Implement of '&=' operator."""
        for value in (self - it):
            self.discard(value)
        return self

    cpdef bint isdisjoint(self, other):
        """Return True if the set has no elements in common with other.
        Sets are disjoint if and only if their intersection is the empty set.
        """
        for value in other:
            if value in self:
                return False
        return True

    cpdef bint issubset(self, other):
        """Method of '<=' operator."""
        return self <= other

    cpdef bint issuperset(self, other):
        """Method of '>=' operator."""
        return other <= self

    cpdef bint isorderedsubset(self, other):
        """Method of '<=' operator with ordered detection."""
        return _isorderedsubset(self, other)

    cpdef bint isorderedsuperset(self, other):
        """Method of '>=' operator with ordered detection."""
        return _isorderedsubset(other, self)

    def __xor__(self, other) -> OrderedSet:
        """Implement of '^' operator."""
        if not isinstance(self, Iterable):
            return NotImplemented
        if not isinstance(other, Iterable):
            return NotImplemented

        return (self - other) | (other - self)

    def __ixor__(self, other):
        """Implement of '^=' operator."""
        if other is self:
            self.clear()
        else:
            if not isinstance(other, Set):
                other = self._from_iterable(other)
            for value in other:
                if value in self:
                    self.discard(value)
                else:
                    self.add(value)
        return self

    cpdef OrderedSet union(self, other):
        """Method of '|' operator."""
        return self | other

    cpdef void update(self, other):
        """Method of '|=' operator."""
        self |= other

    def __or__(self, other) -> OrderedSet:
        """Implement of '|' operator."""
        ostyp = type(self if isinstance(self, OrderedSet) else other)

        if not isinstance(self, Iterable):
            return NotImplemented
        if not isinstance(other, Iterable):
            return NotImplemented
        chain = (e for s in (self, other) for e in s)
        return ostyp._from_iterable(chain)

    def __ior__(self, other) -> OrderedSet:
        """Implement of '|=' operator."""
        for elem in other:
            _add(self, elem)
        return self

    ##
    # list methods
    ##
    cpdef int index(self, elem):
        """Return the index of `elem`. Rases :class:`ValueError` if not in the OrderedSet."""
        if elem not in self:
            raise ValueError(f"{elem} is not in {type(self).__name__}")
        cdef Entry curr = self.end.next
        cdef ssize_t index = 0
        while curr.key != elem:
            curr = curr.next
            index += 1
        return index

    cdef OrderedSet _getslice(self, slice item):
        cdef ssize_t start, stop, step, slicelength, place, i
        cdef Entry curr
        cdef OrderedSet result
        PySlice_GetIndicesEx(item, len(self), &start, &stop, &step, &slicelength)

        result = type(self)()
        place = start
        curr = self.end

        if slicelength <= 0:
            pass
        elif step > 0:
            # normal forward slice
            i = 0
            while slicelength > 0:
                while i <= place:
                    curr = curr.next
                    i += 1
                _add(result, curr.key)
                place += step
                slicelength -= 1
        else:
            # we're going backwards
            i = len(self)
            while slicelength > 0:
                while i > place:
                    curr = curr.prev
                    i -= 1
                _add(result, curr.key)
                place += step
                slicelength -= 1
        return result

    cdef object _getindex(self, ssize_t index):
        cdef ssize_t _len = len(self)
        if index >= _len or (index < 0 and abs(index) > _len):
            raise IndexError("list index out of range")

        cdef Entry curr
        if index >= 0:
            curr = self.end.next
            while index:
                curr = curr.next
                index -= 1
        else:
            index = abs(index) - 1
            curr = self.end.prev
            while index:
                curr = curr.prev
                index -= 1
        return curr.key

    def __getitem__(self, item):
        """Implement of '[]' operator."""
        if isinstance(item, slice):
            return self._getslice(item)
        if not PyIndex_Check(item):
            raise TypeError(f"{type(self).__name__} indices must be integers, not {type(item)}")
        return self._getindex(item)

    cpdef void reverse(self):
        """Reverse objects."""
        cdef list my_iter = list(OrderedSetReverseIterator(self))
        self.clear()
        self.update(my_iter)

    ##
    # sequence methods
    ##
    def __len__(self) -> int:
        """Implement of 'len()' operator."""
        return len(self.map)

    def __contains__(self, elem) -> bool:
        """Implement of 'in' operator."""
        return elem in self.map

    def __iter__(self) -> OrderedSetIterator:
        """Implement of 'iter()' operator. (reference method)"""
        return OrderedSetIterator.__new__(OrderedSetIterator, self)

    def __reversed__(self) -> OrderedSetReverseIterator:
        """Implement of 'reversed()' operator."""
        return OrderedSetReverseIterator.__new__(OrderedSetReverseIterator, self)

    def __reduce__(self):
        items = list(self)
        inst_dict = vars(self).copy()
        return self.__class__, (items, ), inst_dict

    def __repr__(self) -> str:
        """Implement of '!r' operator in string."""
        if not self:
            return f'{self.__class__.__name__}()'
        return f'{self.__class__.__name__}({list(self)!r})'

    def __eq__(self, other) -> bool:
        """Implement of '==' operator."""
        if isinstance(other, (OrderedSet, list)):
            return len(self) == len(other) and list(self) == list(other)
        elif isinstance(other, Set):
            return set(self) == set(other)
        return NotImplemented

    def __le__(self, other) -> bool:
        """Implement of '<=' operator."""
        if isinstance(other, Set):
            return len(self) <= len(other) and set(self) <= set(other)
        elif isinstance(other, list):
            return len(self) <= len(other) and list(self) <= list(other)
        return NotImplemented

    def __lt__(self, other) -> bool:
        """Implement of '<' operator."""
        if isinstance(other, Set):
            return len(self) < len(other) and set(self) < set(other)
        elif isinstance(other, list):
            return len(self) < len(other) and list(self) < list(other)
        return NotImplemented

    def __ge__(self, other) -> bool:
        """Implement of '>=' operator."""
        ret = self < other
        if ret is NotImplemented:
            return ret
        return not ret

    def __gt__(self, other) -> bool:
        """Implement of '>' operator."""
        ret = self <= other
        if ret is NotImplemented:
            return ret
        return not ret
