///|
fn main {
  let bench = @benchmark.Bench()
  bench.bench(
    () => bench.keep(@policy.run() catch { error => abort(error.to_string()) }),
    name="aws-ec2-policy.parse-and-evaluate",
    count=7U,
  )
  println(bench.dump_summaries())
}
