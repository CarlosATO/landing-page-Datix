import { NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

export async function POST(request) {
    try {
        const stripe = new Stripe(process.env.STRIPE_SECRET_KEY)

        const supabase = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL,
            process.env.SUPABASE_SERVICE_ROLE_KEY
        )

        const { companyId } = await request.json()

        if (!companyId) {
            return NextResponse.json({ error: 'Company ID is required' }, { status: 400 })
        }

        const { data: company, error } = await supabase
            .from('companies')
            .select('stripe_customer_id')
            .eq('id', companyId)
            .single()

        if (error || !company || !company.stripe_customer_id) {
            return NextResponse.json({ error: 'Company or Stripe Customer ID not found' }, { status: 400 })
        }

        const session = await stripe.billingPortal.sessions.create({
            customer: company.stripe_customer_id,
            return_url: 'http://localhost:3000/portal',
        })

        return NextResponse.json({ url: session.url })

    } catch (err) {
        console.error('Stripe Portal Error:', err)
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
    }
}
