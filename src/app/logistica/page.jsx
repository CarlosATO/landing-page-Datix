import { redirect } from 'next/navigation';

export default function LogisticaPage() {
  redirect(process.env.NEXT_PUBLIC_LOGISTICA_APP_URL || 'http://localhost:5176/');
}
