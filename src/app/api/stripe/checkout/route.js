import Stripe from 'stripe';
import { NextResponse } from 'next/server';
import { requireCompanyMembership } from '@/lib/server/supabase';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export async function POST(request) {
    try {
        // Lee el body para buscar el companyId que manda el Frontend
        const body = await request.json();

        const context = await requireCompanyMembership(request, body.companyId, ['OWNER', 'MANAGER']);
        if (context.error) {
            return NextResponse.json({ error: context.error }, { status: context.status || 400 });
        }

        if (!body.companyId) {
            return NextResponse.json({ error: "No se proporcionó companyId." }, { status: 400 });
        }

        const session = await stripe.checkout.sessions.create({
            client_reference_id: body.companyId, // <-- Stripe enlazará el pago a este ID
            payment_method_types: ['card'],
            mode: 'subscription',
            line_items: [
                {
                    price: process.env.STRIPE_PRICE_ID_POS,
                    quantity: 1,
                },
            ],
            success_url: `${request.headers.get('origin')}/portal?success=true`,
            cancel_url: `${request.headers.get('origin')}/portal?canceled=true`,
        });

        return NextResponse.json({ url: session.url });
    } catch (err) {
        console.error('Error creando sesión de Stripe:', err);
        return NextResponse.json({ error: err.message }, { status: 500 });
    }
}
