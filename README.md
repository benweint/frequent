# Frequent

Frequent is a little Ruby metaprogramming demo gem that can keep track of what's
happening during your Ruby program's execution - specifically, how many times a
targeted method is called.

## Usage

To use frequent, install the gem, then `require 'frequent'` in one of your source
files and set the `COUNT_CALLS_TO` environment variable to the name of the
method you'd like to count calls to. Like this:

```
require 'frequent'

100.times do
  puts "hello, frequent".split(',').inspect
end
```

```
$ COUNT_CALLS_TO='String#split' ruby test.rb
...
String#split called 100 times
```

Following Ruby conventions, instance methods are identified with a hash
(e.g. `String#split`), and class methods are identified with a period
(e.g. `File.join`).

### API

You can also use the `Frequent` module to manually place probes in your code:

```
probe = Frequent.instrument('MyClass#instance_method')
...
probe.calls # number of calls to target since instrumentation
```

If you're only interested in capturing calls during a specific part of your
code's execution, you can pass a block to `instrument`, during which
instrumentation will be enabled:

```
probe = Frequent.instrument('MyClass.method') do
  ...
end
probe.calls # number of calls to target that happened in the block
```

Your targetd class/module and method need not be defined yet at the time of
instrumentation, but see the performance section below for notes about the
performance implementations of instrumenting not-yet-defined targets.

## Internals

Frequent works by overwriting the original implementation of the targeted method
with an instrumented version that keeps a call count, using Ruby's `class_eval`,
`alias_method`, and `define_method` facilities. The original version of the
instrumented method is saved so that it can be optionally restored after
instrumentation.

## Performance

Frequent is relatively low-overhead, but there are a few things to keep in mind
regarding performance:

1. You'll get better performance if you place your probes *after* your target
   method has been defined. Frequent will attempt to place your probe immediately
   upon calls to `Frequent.instrument`, but if it ever encounters a probe that it
   cannot place yet due to a missing host class/module or method, it will make
   use of the `method_added`, `singleton_method_added`, and `included` hooks in
   Ruby.

   These hooks will cause a bit of code to execute each time a new method is
   added to a Ruby module in your process, and each time a module is included
   in a new class. Frequent uses these hooks so that it has a chance to place
   instrumentation as soon as your targeted class/module and method become
   available.

   Most Ruby processes don't add many additional methods or create additional
   classes after an initial start-up sequence, meaning that the performance
   impact of using these hooks should be generally limited to a slightly higher
   fixed start-up cost for your process.

2. Calls to instrumented methods will be slower than calls to uninstrumented
   methods. Only methods that are actually instrumented will be subject to this
   added overhead.

   The degree to which this affects your program's performance in practice will
   depend heavily on how hot your instrumented method is.
   Instrumentation of a method called in a tight loop many times during your
   program's execution will be more expensive overall than instrumentation of a
   method only called a few times during the life of your program.

The benchmark in `spec/frequent_spec.rb` (run with `bundle exec rake test BENCH=1`)
attempts to measure the overhead incurred by instrumentation of a method with
Frequent. The benchmark compares times to call empty instrumented and
uninstrumented methods (both class and instance methods).

When interpreting the results, keep in mind that most methods worth
instrumenting are not empty -- that is, they do some non-trivial work that will
help amortize the per-call overhead.

Benchmark results will vary from machine to machine (and between different Ruby
implementations), but on the author's machine, the overhead introduced by 
instrumenting a method is ~0.5 μs / call. This represents a slowdown of about
2.5x - 7x for a completely empty method call (depending on whether a class or
instance method is being instrumented).

## Caveats

### method_missing

In Ruby, it's fairly common to encounter methods that aren't explicitly defined,
but are instead dynamically implemented using Ruby's `method_missing` facility.
Frequent will not work for methods defined in this way.

The main challenge in dealing with methods defined through `method_missing` is
knowing when to place instrumentation. In order for instrumentation of
`method_missing` methods to work, probes must be placed immediately upon
creation of the targeted class or module - `method_added` is of no use here,
since the target method is never actually added.

There's unfortunately no `const_added` hook available in Ruby (though there was
discussion on the mailing list of adding one a while ago), and the author has
not found any alternatives for detecting module / class creation that he finds
sufficiently robust, simple, and performant.

Alternatives include using `set_trace_func` temporarily until the target class
or method has been created and then disabling it (slow and complex) and looking
for placeable probes after each `require` or `load` (doesn't work for 
dynamically-created classes).

### Metaprogramming

Frequent isn't magic - it relies on the same hooks and facilities that are made
available by the Ruby interpreter to any code in your program. That means it's
probably possible to break or trick it in many ways.

### Instrumenting the same target multiple times

This won't work, and should probably raise an exception, but currently just
fails.

## Author

Ben Weintraub - benweint@gmail.com