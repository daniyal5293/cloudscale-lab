const STEPS = [
  {
    title: "1. Request arrives at the load balancer",
    body: "Your browser connects to the Application Load Balancer's public DNS name on port 80. The ALB runs in two Availability Zones, so losing one zone does not take the site down.",
  },
  {
    title: "2. ALB picks a healthy target",
    body: "The ALB forwards each HTTP request to a registered EC2 instance in its target group, choosing only targets that are currently passing the /api/health check. Requests are spread across targets (round robin by default).",
  },
  {
    title: "3. An instance answers",
    body: "Each instance runs the same Docker container. The app is stateless (no sessions, no local database), so any instance can answer any request and the result is identical apart from the instance identity.",
  },
  {
    title: "4. CloudWatch measures the load",
    body: "The ALB publishes RequestCountPerTarget to CloudWatch every minute. The Auto Scaling target-tracking policy compares it with the configured target value.",
  },
  {
    title: "5. Auto Scaling adjusts capacity",
    body: "Sustained load above the target triggers scale-out: new instances boot, pull the container image and join the target group once healthy. Sustained low load triggers scale-in, and instances are drained and terminated.",
  },
];

export function HowItWorks() {
  return (
    <section className="card">
      <h2>How load balancing and auto-scaling work here</h2>
      <ol className="steps">
        {STEPS.map((step) => (
          <li key={step.title}>
            <h3>{step.title}</h3>
            <p>{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
