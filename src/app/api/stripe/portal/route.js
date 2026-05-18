import { NextResponse } from 'next/server'
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'
import { requireCompanyMembership } from '@/lib/server/supabase'

export async function POST(request) {
    try {
        const body = await request.json()
        const { companyId } = body

        const context = await requireCompanyMembership(request, companyId, ['OWNER', 'MANAGER'])
        if (context.error) {
            return NextResponse.json({ error: context.error }, { status: context.status || 400 })
        }

        const stripe = new Stripe(process.env.STRIPE_SECRET_KEY)

        const supabase = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL,
            process.env.SUPABASE_SERVICE_ROLE_KEY
        )

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
            return_url: `${request.headers.get('origin') || 'http://localhost:3000'}/portal`,
        })

        return NextResponse.json({ url: session.url })

    } catch (err) {
        console.error('Stripe Portal Error:', err)
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
    }
}
