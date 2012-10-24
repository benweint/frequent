require 'spec_helper'

describe Frequent do
  before :each do
    class Potato
      def instance_method; end
      def block_method(x); yield x; end
      def self.class_method(*args); end

      def self.recursive_class_method(n)
        return if n == 1
        recursive_class_method(n-1)
      end

      def self.respond_to?(method)
        method.to_s == 'class_missing_method' ? true : super
      end

      def overridden_method; end

      protected
      def protected_instance_method; end

      private
      def private_instance_method; end
    end

    class RedPotato < Potato
      def overridden_method; end
    end
  end

  describe 'probe name parsing' do
    it 'should raise ProbeNameError on invalid probe name' do
      proc { Frequent.instrument("Lava$monster") }.must_raise(Frequent::ProbeNameError)
    end
  end

  describe 'instance method instrumentation' do
    it 'should support simple method call counting' do
      p = Frequent.instrument('Potato#instance_method')
      11.times { Potato.new.instance_method }
      p.calls.must_equal(11)
    end

    it 'should apply to already-created instances' do
      instance = Potato.new
      p = Frequent.instrument('Potato#instance_method')
      3.times { instance.instance_method }
      p.calls.must_equal(3)
    end

    it 'should not count calls identically-named methods from parent class' do
      p0 = Frequent.instrument('Potato#overridden_method')
      p1 = Frequent.instrument('RedPotato#overridden_method')
      2.times { Potato.new.overridden_method }
      3.times { RedPotato.new.overridden_method }
      p0.calls.must_equal(2)
      p1.calls.must_equal(3)
    end

    it 'should support private / protected methods' do
      p0 = Frequent.instrument('Potato#private_instance_method')
      p1 = Frequent.instrument('Potato#protected_instance_method')
      3.times { Potato.new.send(:private_instance_method) }
      4.times { Potato.new.send(:protected_instance_method) }
      p0.calls.must_equal(3)
      p1.calls.must_equal(4)
    end

    it 'should support instrumenting methods on Object' do
      p = Frequent.instrument('Object#tainted?') do
        Object.new.tainted?
      end
      p.calls.must_equal(1)
    end

    it 'should pass-thru blocks and args' do
      v = nil
      p = Frequent.instrument('Potato#block_method')
      Potato.new.block_method(42) { |n| v = n }
      v.must_equal(42)
      p.calls.must_equal(1)
    end
  end

  describe 'instrumentation of class methods' do
    it 'should support simple call counting' do
      p = Frequent.instrument('Potato.class_method')
      9.times { Potato.class_method }
      p.calls.must_equal(9)
    end

    it 'should support recursive methods' do
      p = Frequent.instrument('Potato.recursive_class_method')
      Potato.recursive_class_method(7)
      p.calls.must_equal(7)
    end
  end

  describe 'probe removal' do
    it 'should remove probes on instance methods' do
      p = Frequent.instrument('Potato#instance_method')
      Potato.new.instance_method
      p.disable!
      Potato.new.instance_method
      p.calls.must_equal(1)
    end

    it 'should remove probes on class methods' do
      p = Frequent.instrument('Potato.class_method')
      Potato.class_method
      p.disable!
      Potato.class_method
      p.calls.must_equal(1)
    end

    it 'should instrument scoped to block' do
      p = Frequent.instrument('Potato#instance_method') do
        5.times { Potato.new.instance_method }
      end
      3.times { Potato.new.instance_method }
      p.calls.must_equal(5)
    end
  end

  describe 'instrumentation of modules' do
    it 'should catch module methods even if included after instrumentation' do
      module Mod1
        def demo; end
      end

      p = Frequent.instrument('Mod1#demo')

      class Dummy1
        include Mod1
      end
      Dummy1.new.demo

      p.calls.must_equal(1)
    end

    it 'should work if probe placed before module/class definition' do
      p = Frequent.instrument('Dummy3#foo')

      module Dummy2; def foo; end; end
      class Dummy3; include Dummy2; end

      10.times { Dummy3.new.foo }

      p.calls.must_equal(10)
    end

    it 'should work for module methods' do
      p = Frequent.instrument('Dummy5.foo')
      module Dummy5; def self.foo; end; end
      5.times { Dummy5.foo }
      p.calls.must_equal(5)
    end

    it 'should work with nested modules' do
      p = Frequent.instrument('Dummies::Dummy6.foo')

      module Dummies
        module Dummy6; def self.foo; end; end
      end

      5.times { Dummies::Dummy6.foo }
      p.calls.must_equal(5)
    end
  end

  it 'should work if method is added to class after instrumentation' do
    class Dummy7; end

    p = Frequent.instrument('Dummy7#foo')

    class Dummy7; def foo; end; end

    3.times { Dummy7.new.foo }
    p.calls.must_equal(3)
  end

  it 'should work for dynamically-created classes' do
    p = Frequent.instrument('Dummy8.foo')

    eval "class Dummy8; def self.foo; end; end; 5.times { Dummy8.foo }"

    p.calls.must_equal(5)
  end

  if ENV['BENCH']
    it 'should be fast' do
      p = Potato.new
      n = 1000000

      puts "Trials: #{n}"
      Benchmark.bmbm do |rpt|
        rpt.report("Uninstrumented instance method") do
          n.times { p.instance_method }
        end

        rpt.report("Instrumented instance method") do
          Frequent.instrument('Potato#instance_method') do
            n.times { p.instance_method }
          end
        end

        rpt.report("Uninstrumented class method") do
          n.times { Potato.class_method }
        end
        
        rpt.report("Instrumented class method") do
          Frequent.instrument("Potato.class_method") do
            n.times { Potato.class_method }
          end
        end
      end
    end
  end
end
