import { HowItWorks } from "@/components/HowItWorks";
import { InstanceCard } from "@/components/InstanceCard";
import { LiveDistribution } from "@/components/LiveDistribution";
import { ScalingInfo } from "@/components/ScalingInfo";
import { getScalingConfig } from "@/lib/config";
import { getInstanceIdentity } from "@/lib/metadata";

// Render on every request so the card shows the instance that served *this* page.
export const dynamic = "force-dynamic";

export default async function HomePage() {
  const identity = await getInstanceIdentity();
  const config = getScalingConfig();
  const renderedAt = new Date().toISOString();

  return (
    <main className="container">
      <header className="hero">
        <p className="eyebrow">AWS DevOps Demonstration</p>
        <h1>CloudScale Lab</h1>
        <p className="subtitle">Load Balancing and Auto-scaling Demonstrator</p>
        <p className="lead">
          This page is served by one of several identical, stateless EC2 instances behind an AWS
          Application Load Balancer. An EC2 Auto Scaling Group adds instances when traffic rises and
          removes them when it falls. Reload the page or use the distribution tester below to see
          different instances answer.
        </p>
      </header>

      <div className="grid">
        <InstanceCard identity={identity} renderedAt={renderedAt} appVersion={config.appVersion} />
        <ScalingInfo config={config} />
      </div>

      <LiveDistribution />
      <HowItWorks />

      <footer className="footer">
        CloudScale Lab · Next.js on Docker · EC2 Auto Scaling · Application Load Balancer · CloudWatch
      </footer>
    </main>
  );
}
