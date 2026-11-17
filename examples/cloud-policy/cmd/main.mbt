///|
fn main {
  let report = @policy.run() catch { error => abort(error.to_string()) }
  if @env.args().contains("--full") {
    println(report.stringify())
  } else {
    println(@policy.summary(report).stringify())
  }
}
