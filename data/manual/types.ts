export interface ManualTask {
  heading: string
  steps: string[]
}

export interface ManualModule {
  key: string
  route?: string
  icon: string
  title: string
  purpose: string
  statuses?: string
  tasks: ManualTask[]
  tips?: string[]
}

export interface ManualSection {
  key: string
  title: string
  modules: ManualModule[]
}
