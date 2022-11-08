# zanzibar-experiments

This is a proof of concept implementation of the Zanzibar ACL in Ruby + sqlite.

This implementation supports `check?` and `enumerate`.

```
bundle i
ruby main.rb
```

Use `--report` flag to include a CSV report at the end of the run:
![image](https://user-images.githubusercontent.com/40670/200466330-46336fd4-af3e-40b2-8147-dfb614f8dfa0.png)


Related projects/services

* [Zanzibar PG](https://github.com/josephglanville/zanzibar-pg) proof of concept implementation of the Zanzibar ACL language in pure PL/pgSQL
