import Stripe from 'stripe';
import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

// Inicialización de Stripe y Supabase Admin (fuera del handler)
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Usamos la Service Role Key para tener permisos de administrador y bypass sobre los RLS
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

export async function POST(req) {
    // 1. Lectura del Body en crudo y la firma en App Router
    const body = await req.text();
    const signature = req.headers.get('stripe-signature');

    let event;

    // 2. Validación criptográfica de Stripe
    try {
        event = stripe.webhooks.constructEvent(
            body,
            signature,
            process.env.STRIPE_WEBHOOK_SECRET
        );
    } catch (err) {
        console.error(`Error de firma del Webhook: ${err.message}`);
        return NextResponse.json({ error: `Webhook Error: ${err.message}` }, { status: 400 });
    }

    // 3. Lógica de Negocio
    try {
        switch (event.type) {
            case 'checkout.session.completed': {
                const session = event.data.object;
                const companyId = session.client_reference_id;
                const customerId = session.customer;
                const subscriptionId = session.subscription;

                if (companyId) {
                    const { error: updateError } = await supabaseAdmin
                        .from('companies')
                        .update({
                            stripe_customer_id: customerId,
                            stripe_subscription_id: subscriptionId,
                            subscription_status: 'active'
                        })
                        .eq('id', companyId);

                    if (updateError) {
                        console.error("Error al actualizar la tabla 'companies' tras Checkout:", updateError);
                        throw updateError;
                    }
                    console.log(`✅ Pago exitoso. Empresa ${companyId} vinculada a Stripe Customer ${customerId}.`);
                }
                break;
            }

            case 'customer.subscription.created':
            case 'customer.subscription.updated':
            case 'customer.subscription.deleted': {
                const subscription = event.data.object;
                const stripeCustomerId = subscription.customer;

                // Extraer el price_id (asumiendo 1 producto base)
                const priceId = subscription.items.data[0]?.price.id;

                const { error: updateSubError } = await supabaseAdmin
                    .from('companies')
                    .update({
                        stripe_subscription_id: subscription.id,
                        stripe_price_id: priceId,
                        subscription_status: subscription.status,
                        current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
                    })
                    .eq('stripe_customer_id', stripeCustomerId);

                if (updateSubError) {
                    console.error("❌ Error al actualizar la suscripción en 'companies':", updateSubError);
                    throw updateSubError;
                }

                console.log(`📦 Estado de suscripción (${subscription.status}) actualizado para Customer: ${stripeCustomerId}`);
                break;
            }

            default:
                console.log(`Evento ignorado: ${event.type}`);
        }
    } catch (error) {
        console.error('❌ Error manejando evento de webhook:', error);
        return NextResponse.json({ error: 'Webhook handler failed.' }, { status: 500 });
    }

    // 4. Respuesta Exitosa requerida por Stripe
    return NextResponse.json({ received: true }, { status: 200 });
}
