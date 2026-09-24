export type Mood = 'beaming' | 'content' | 'meh' | 'grumpy' | 'furious' | 'pending'

export const MOODS: readonly Mood[] = ['beaming', 'content', 'meh', 'grumpy', 'furious', 'pending']

export function moodLabel(mood: Mood): string {
  switch (mood) {
    case 'beaming':
      return 'Beaming'
    case 'content':
      return 'Content'
    case 'meh':
      return 'Meh'
    case 'grumpy':
      return 'Grumpy'
    case 'furious':
      return 'Furious'
    case 'pending':
      return 'Still reading'
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}

export function moodBlurb(mood: Mood): string {
  switch (mood) {
    case 'beaming':
      return 'over the moon'
    case 'content':
      return 'quietly pleased'
    case 'meh':
      return 'shrugging'
    case 'grumpy':
      return 'not impressed'
    case 'furious':
      return 'steaming'
    case 'pending':
      return 'we are still reading this one'
    default: {
      const unhandled: never = mood
      return unhandled
    }
  }
}
