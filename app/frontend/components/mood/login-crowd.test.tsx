import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import LoginCrowd, { LOGIN_CROWD } from './login-crowd'

describe('LoginCrowd', () => {
  it('is a mostly happy crowd with one grumpy face and one storm cloud', () => {
    const moods = LOGIN_CROWD.map((extra) => extra.mood)
    const happy = moods.filter((mood) => mood === 'beaming' || mood === 'content')

    expect(happy.length).toBeGreaterThan(moods.length / 2)
    expect(moods.filter((mood) => mood === 'grumpy')).toHaveLength(1)
    expect(moods.filter((mood) => mood === 'furious')).toHaveLength(1)
  })

  it('keeps the grumpy and stormy faces in the phone-sized middle', () => {
    const onPhones = LOGIN_CROWD.filter((extra) => extra.visible === 'always').map((extra) => extra.mood)

    expect(onPhones).toHaveLength(5)
    expect(onPhones).toEqual(expect.arrayContaining(['grumpy', 'furious']))
  })

  it('draws made-up people only, hidden from assistive tech', () => {
    const { container } = render(<LoginCrowd />)
    const crowd = screen.getByTestId('login-crowd')

    expect(crowd).toHaveAttribute('aria-hidden', 'true')
    expect(LOGIN_CROWD.every((extra) => extra.seed.startsWith('login-'))).toBe(true)
    expect(container.querySelectorAll('svg[data-mood]')).toHaveLength(LOGIN_CROWD.length)
    expect(container.querySelectorAll('.hh-idle')).toHaveLength(LOGIN_CROWD.length)
    expect(crowd).toHaveTextContent('Welcome back!')
  })
})
