export type PairingRuntime = {
  host: string;
  port: number;
  certificateFingerprint: string;
};

let runtime: PairingRuntime | undefined;

export function setPairingRuntime(value: PairingRuntime): void {
  runtime = value;
}

export function clearPairingRuntime(): void {
  runtime = undefined;
}

export function getPairingRuntime(): PairingRuntime | undefined {
  return runtime;
}
