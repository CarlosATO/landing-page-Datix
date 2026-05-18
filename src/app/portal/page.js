"use client";

import { usePortalDashboard } from './hooks/usePortalDashboard';
import { PortalDashboardView } from './components/PortalDashboardView';

export default function PortalPage() {
  const portal = usePortalDashboard();
  return <PortalDashboardView {...portal} />;
}
