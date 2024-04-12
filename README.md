# SQL Tree Data Structure Implementation

This repository contains example implementations of tree
data structures in SQL. Trees are hierarchical data
structures commonly used to represent relationships between
entities where each entity has a parent and zero or more
children. Implementing trees in SQL can be useful for
various applications, including organizational hierarchies,
file systems, forum threads and replies, classification
through deeper and deeper subcategories.

There are many ways to implement trees in SQL. None of which
is the best. Each has its own advantages and drawbacks in
areas such as ease of quering, data redudancy, data
integrity, performance and ease of implementation.
Programmer's job is to pick the one best suited for their
particular use-case.

## Implementation Using Adjacency List

In the adjacency list model, each node in the tree is stored
as a row in a table, and each row contains a reference to
its parent node. Here's how the implementation works:

* Table Structure: Create a table with columns nodeId,
  parentId, and any additional columns for node values or
  metadata.
* Insertion: To insert a new node, simply add a new row to
  the table with the appropriate nodeId and parentId values.
* Queries: Queries involving parent-child relationships can
  be efficiently performed using joins between the table and
  itself.

## Implementation Using Path Enumeration

In the path enumeration model, each node in the tree is
identified by its path from the root node. Here's how the
implementation works:

* Table Structure: Create a table with columns path and
  value, where path represents the path from the root node to
  the current node, and value represents the value of the
  node.
* Insertion: To insert a new node, calculate its path from
  the root node and insert a new row into the table with the
  calculated path and node value.
* Queries: Queries involving parent-child relationships can
  be achieved by querying rows based on their paths and
  performing string operations to extract parent-child
  relationships.

## Usage

Both implementations are provided as separate T-SQL scripts
(`adjacency_list.sql` and `path_enumeration.sql`) along with
sample data, example queries and comments to demonstrate their
usage.
