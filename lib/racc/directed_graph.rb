require 'racc/util'
require 'set'

module Racc
  module Graph
    # An implementation which is fast when the exact number of nodes is known
    # in advance, and each one can be identified by an integer
    class Finite < Array
      def initialize(size)
        super(size) { Set.new }
      end

      def add_child(from, to)
        self[from] << to
        to
      end

      def remove_child(from, to)
        self[from].delete(to)
      end

      alias nodes each_index

      def children(node, &block)
        result = self[node]
        result.each(&block) if block_given?
        result
      end

      def reachable(start)
        Racc.set_closure([start]) { |node| self[node] }
      end

      def leaves(start)
        reachable(start).select { |node| self[node].empty? }
      end

      # shortest path between nodes; both start and end points are included
      def path(start, dest)
        # Dijkstra's algorithm
        return [start] if start == dest

        visited  = Set[start]
        worklist = children(start)
        paths    = {start => [start]}

        until visited.include?(dest)
          return nil if worklist.empty?
          node = worklist.min_by { |n| paths[n].size }
          node_path = paths[node]

          children(node) do |child|
            child_path = paths[child]
            if child_path.nil? || child_path.size > node_path.size + 1
              paths[child] = node_path.dup << child
            end
            worklist << child unless visited.include?(child)
          end

          visited << node
        end

        paths[dest]
      end

      # { node -> shortest path to it }
      # if a block is provided, it is a 'cost function'
      def all_paths(start)
        # again, Dijkstra's algorithm
        paths = {start => [0, start]} # cache total path cost

        Racc.set_closure([start]) do |node|
          node_path = paths[node]
          children(node) do |child|
            child_path = paths[child]
            cost = block_given? ? yield(node, child) : 1
            if child_path.nil? || child_path[0] > node_path[0] + cost
              paths[child] = node_path.dup.tap { |p| p[0] += cost } << child
            end
          end
        end

        paths.each_value { |p| p.shift } # drop cached total costs
        paths
      end

      def dup
        super.map!(&:dup)
      end
    end

    # Like Graph::Finite, but with backpointers from children to parents as well
    class Reversible < Finite
      def initialize(size)
        super(size * 2)
        @offset = size
      end

      def add_child(from, to)
        self[from] << to
        self[@offset + to] << from
        to
      end

      def remove_child(from, to)
        self[from].delete(to)
        self[@offset + to].delete(from)
      end

      def remove_node(node)
        self[node].each { |child| self[@offset + child].delete(node) }.clear
        self[@offset + node].each { |parent| self[parent].delete(node) }.clear
      end

      def nodes(&block)
        result = 0...@offset
        result.each(&block) if block_given?
        result
      end

      def parents(node, &block)
        result = self[@offset + node]
        result.each(&block) if block_given?
        result
      end

      # All nodes which can reach a node in `dests` (and `dests` themselves)
      def can_reach(dests)
        Racc.set_closure(dests) { |node| self[@offset + node] }
      end

      def reachable_from(nodes)
        Racc.set_closure(nodes) do |node|
          self[node]
        end
      end
    end

    # This implementation uses an object for each node, rather than identifying
    # nodes by integers
    # this means we can add as many nodes as we want
    # Graph::Node can also be subclassed and have extra methods added
    class Generic
      def initialize
        @nodes = Set.new
        @start = nil
      end

      attr_reader :nodes, :start

      def start=(node)
        @nodes << node
        @start = node
      end

      def remove_node(node)
        @start = nil if node == @start
        @nodes.delete(node)
        node.out.each { |other| other.in.delete?(node) }
        node.in.each  { |other| other.out.delete?(node) }
      end

      def add_child(from, to)
        @nodes   << to
        from.out << to
        to.in    << from
        to
      end

      def remove_child(from, to)
        from.out.delete(to)
        to.in.delete(from)
      end

      def children(node)
        node.out
      end

      def reachable
        reachable_from([@start])
      end

      def reachable_from(nodes)
        Racc.set_closure(nodes) { |node| node.out }
      end

      def can_reach(dests)
        Racc.set_closure(dests) { |node| node.in }
      end

      def leaves
        @nodes.select { |node| node.out.empty? }
      end

      # { node -> shortest path to it }
      # if a block is provided, it is a 'cost function'
      # all paths include both start and end points
      def all_paths
        return {} if @start == nil

        # Dijkstra's algorithm
        paths = {@start => [0, @start]} # cache total cost of path

        Racc.set_closure([@start]) do |node|
          node_path = paths[node]
          node.out.each do |child|
            child_path = paths[child]
            cost = block_given? ? yield(node, child) : 1
            if child_path.nil? || child_path[0] > node_path[0] + cost
              paths[child] = node_path.dup.tap { |p| p[0] += cost } << child
            end
          end
        end

        paths.each_value { |path| path.shift } # drop cached total costs
        paths
      end
    end

    class Node
      def initialize
        @out, @in = Set.new, Set.new
      end

      attr_reader :out, :in
    end
  end
end