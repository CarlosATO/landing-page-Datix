import Stripe from 'stripe';
import { NextResponse } from 'next/server';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export async function POST(request) {
    try {
        // Lee el body para buscar el companyId que manda el Frontend
        const body = await request.json();

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
