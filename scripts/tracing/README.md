This folder contains Python scripts to automatically trace the GitHub workflows execution steps and success/failure to Azure Kusto. These Python scripts rely on a "state file", stored under $HOME, to simplify usage and avoid code duplication.

`new_run.py` will generate a unique run ID and this will be used to associate all the steps traced to this run.

"Step" here is designed to mirror the GitHub workflow steps, although the exact steps traced doesn't have to strictly match the GitHub workflow.

The workflow should then call `trace_step.py` for each workflow step. Passing in `--start <step name>` will trace the start of a step. Passing in `--complete` (no need to pass in step name this time) will trace the end of a step. For `--complete`, optional output and error string can be attached to the step via `--output key=value`, `--output-from-stdin` or `--err <error message>`. Failure is indicated by the presence of an error message.

If a previous step is not completed when `--start` is passed, it will also mark the previous step as complete (assuming success).

Instead of calling `trace_step.py --complete` manually for each step, `../trace_run_result.sh` can be called in an `if: always()` step in the workflow to ensure failures for all steps up to that point are traced. Manually calling `trace_step.py --complete` is still sometimes necessary to attach output and more useful error messages.
