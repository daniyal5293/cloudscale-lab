/**
 * Runtime configuration injected by the EC2 user-data script (docker run -e ...).
 * Terraform passes the same values it uses to build the Auto Scaling Group, so
 * the page always shows the configuration that is actually deployed.
 */
export interface ScalingConfig {
  minSize: string;
  desiredCapacity: string;
  maxSize: string;
  targetRequestsPerTarget: string;
  instanceType: string;
  region: string;
  appVersion: string;
}

const NOT_SET = "not set (local)";

export function getScalingConfig(): ScalingConfig {
  return {
    minSize: process.env.ASG_MIN ?? NOT_SET,
    desiredCapacity: process.env.ASG_DESIRED ?? NOT_SET,
    maxSize: process.env.ASG_MAX ?? NOT_SET,
    targetRequestsPerTarget: process.env.SCALING_TARGET ?? NOT_SET,
    instanceType: process.env.INSTANCE_TYPE ?? NOT_SET,
    region: process.env.AWS_REGION ?? NOT_SET,
    appVersion: process.env.APP_VERSION ?? "dev",
  };
}

/** Headers that stop browsers, the ALB and any intermediary from caching. */
export const NO_STORE_HEADERS = {
  "Cache-Control": "no-store, no-cache, max-age=0, must-revalidate",
} as const;
