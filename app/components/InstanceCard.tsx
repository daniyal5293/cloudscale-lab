import type { InstanceIdentity } from "@/lib/metadata";
import { HealthBadge } from "./HealthBadge";

interface Props {
  identity: InstanceIdentity;
  renderedAt: string;
  appVersion: string;
}

export function InstanceCard({ identity, renderedAt, appVersion }: Props) {
  const isLocal = identity.source === "local-fallback";

  return (
    <section className="card">
      <div className="card-header">
        <h2>Instance serving this page</h2>
        <HealthBadge />
      </div>

      <dl className="facts">
        <dt>EC2 instance ID</dt>
        <dd className="mono highlight">{identity.instanceId}</dd>
        <dt>Availability Zone</dt>
        <dd className="mono">{identity.availabilityZone}</dd>
        <dt>Hostname</dt>
        <dd className="mono">{identity.hostname}</dd>
        <dt>Response generated</dt>
        <dd className="mono">{renderedAt}</dd>
        <dt>App version</dt>
        <dd className="mono">{appVersion}</dd>
        <dt>Metadata source</dt>
        <dd className="mono">{identity.source}</dd>
      </dl>

      {isLocal && (
        <p className="note">
          Running outside EC2: the instance metadata service is unreachable, so placeholder values
          are shown. On AWS these come from IMDSv2.
        </p>
      )}
    </section>
  );
}
