import { redirect } from 'next/navigation';

export default function ConstruccionPage() {
  redirect(process.env.NEXT_PUBLIC_CONSTRUCCION_APP_URL || 'http://localhost:5177/construccion');
}
