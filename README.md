# RactorPool

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

Calculating Fibonacci numbers in parallel:

```ruby
fib_worker = lambda do |index|
  first, second = 0, 1
  index.times { first, second = second, first + second }
  [index, first]
end
results = []
pool = RactorPool.new(size: 2, worker: fib_worker) { |result| results << result }

25.times { |index| pool << index }
pool.shutdown

results.sort_by! { |index, _value| index }
results.each { |index, value| puts "fib(#{index}) = #{value}" }

#=> fib(0) = 0
#=> fib(1) = 1
#=> fib(2) = 1
#=> fib(3) = 2
#=> ...
#=> fib(21) = 10946
#=> fib(22) = 17711
#=> fib(23) = 28657
#=> fib(24) = 46368
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake test` to run the
tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joshuay03/ractor-pool. This project is
intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of
conduct](https://github.com/joshuay03/ractor-pool/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RactorPool project's codebases, issue trackers, chat rooms and mailing lists is expected to
follow the [code of conduct](https://github.com/joshuay03/ractor-pool/blob/main/CODE_OF_CONDUCT.md).

## Acknowledgements

Thanks to [Gleb Sinyavskiy (zhulik)](https://github.com/zhulik) for graciously transferring ownership of the
`ractor_pool` gem name, enabling this gem to be published as `ractor-pool`.
