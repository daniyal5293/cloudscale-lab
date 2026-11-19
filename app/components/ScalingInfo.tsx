import type { ScalingConfig } from "@/lib/config";

export function ScalingInfo({ config }: { config: ScalingConfig }) {
  return (
    <section className="card">
      <h2>Current scaling configuration</h2>
      <dl className="facts">
        <dt>Minimum instances</dt>
        <dd className="mono">{config.minSize}</dd>
        <dt>Desired (initial)</dt>
        <dd className="mono">{config.desiredCapacity}</dd>
        <dt>Maximum instances</dt>
        <dd className="mono">{config.maxSize}</dd>
        <dt>Scaling metric</dt>
        <dd className="mono">ALBRequestCountPerTarget</dd>
        <dt>Target value</dt>
        <dd className="mono">{config.targetRequestsPerTarget} req / target / min</dd>
        <dt>Instance type</dt>
        <dd className="mono">{config.instanceType}</dd>
        <dt>Region</dt>
        <dd className="mono">{config.region}</dd>
      </dl>
      <p className="muted">
        Target tracking keeps the average requests per instance near the target value. Above it,
        the Auto Scaling Group launches instances (up to the maximum). When traffic stays below it,
        the group removes instances again (down to the minimum).
      </p>
    </section>
  );
}
