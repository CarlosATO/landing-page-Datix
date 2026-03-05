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

    // 3. Lógica de Negocio (Pago Exitoso)
    if (event.type === 'checkout.session.completed') {
        const session = event.data.object;

        const companyId = session.client_reference_id;
        const customerId = session.customer;
        const subscriptionId = session.subscription;

        // Si la sesión de Stripe nos incluyó a qué Ecosistema de Epresesa pertenece este pago
        if (companyId) {
            const { error: updateError } = await supabaseAdmin
                .from('companies')
                .update({
                    stripe_customer_id: customerId,
                    stripe_subscription_id: subscriptionId,
                    subscription_status: 'active',
                    plan_type: 'BASE_POS'
                })
                .eq('id', companyId);

            if (updateError) {
                console.error("Error al actualizar la tabla 'companies' en Supabase:", updateError);
                // Si la BD falla, registramos el error enviándolo con código 500
                return NextResponse.json({ error: updateError.message }, { status: 500 });
            }

            console.log(`Pago procesado con éxito. Empresa ${companyId} actualizada a plan: BASE_POS.`);
        } else {
            // Ocurre si al crear la sesión en '/api/stripe/checkout' olvidamos enviar el 'client_reference_id'
            console.warn("La sesión del Checkout no trajo consigo el 'client_reference_id' (ID de la empresa).");
        }
    }

    // 4. Respuesta Exitosa requerida por Stripe
    return NextResponse.json({ received: true }, { status: 200 });
}
