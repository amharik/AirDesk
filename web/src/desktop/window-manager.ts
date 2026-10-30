export interface WindowInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface WindowBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DesktopWindowDescriptor {
  id: string;
  title: string;
  icon?: string;
  bounds: WindowBounds;
  minWidth?: number;
  minHeight?: number;
  content?: Node | string;
  appName?: string;
  onFocus?: () => void;
  onBlur?: () => void;
  onMove?: (x: number, y: number) => void;
  onResize?: (width: number, height: number) => void;
  onMinimize?: () => void;
  onMaximize?: () => void;
  onRestore?: () => void;
  onBeforeClose?: () => boolean;
  onClosed?: () => void;
}

export interface DesktopWindowHandle {
  readonly id: string;
  readonly element: HTMLElement;
  readonly body: HTMLElement;
  readonly closed: boolean;
  focus(): void;
  minimize(): void;
  maximize(): void;
  restore(): void;
  close(): void;
  setTitle(title: string): void;
  setBounds(bounds: WindowBounds): void;
  setViewportInsets(insets: WindowInsets): void;
  clientToWindowPoint(clientX: number, clientY: number): { x: number; y: number };
}

export interface WinBoxOptions {
  id?: string;
  root?: Node;
  title?: string;
  icon?: string;
  template?: Node;
  mount?: Node;
  html?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  minwidth?: number;
  minheight?: number;
  top?: number;
  right?: number;
  bottom?: number;
  left?: number;
  class?: string;
  onclose?: () => boolean;
  onfocus?: () => void;
  onblur?: () => void;
  onmove?: (x: number, y: number) => void;
  onresize?: (width: number, height: number) => void;
  onminimize?: () => void;
  onmaximize?: () => void;
  onrestore?: () => void;
}

export interface WinBoxInstance {
  dom: HTMLElement;
  body: HTMLElement;
  title: string;
  min: boolean;
  max: boolean;
  focused: boolean;
  x: number;
  y: number;
  width: number;
  height: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
  focus(): WinBoxInstance;
  minimize(state?: boolean): WinBoxInstance;
  maximize(state?: boolean): WinBoxInstance;
  restore(): WinBoxInstance;
  close(force?: boolean): boolean | undefined;
  resize(width?: number, height?: number): WinBoxInstance;
  move(x?: number, y?: number): WinBoxInstance;
  setTitle(title: string): WinBoxInstance;
}

export type WinBoxFactory = (options: WinBoxOptions) => WinBoxInstance;

export interface WindowManagerOptions {
  root: HTMLElement;
  factory: WinBoxFactory;
  document?: Document;
  insets?: Partial<WindowInsets>;
}

const DEFAULT_INSETS: WindowInsets = { top: 39, right: 0, bottom: 96, left: 0 };

export function createAirDeskWindowTemplate(document: Document): HTMLElement {
  const template = document.createElement('div');
  template.innerHTML =
    '<div class="wb-header airdesk-titlebar titlebar">' +
      '<div class="traffic airdesk-traffic">' +
        '<button class="close" type="button" data-window-action="close" aria-label="Close"><span>×</span></button>' +
        '<button class="min" type="button" data-window-action="minimize" aria-label="Minimize"><span>−</span></button>' +
        '<button class="max" type="button" data-window-action="maximize" aria-label="Maximize"><span>+</span></button>' +
      '</div>' +
      '<div class="wb-drag airdesk-drag">' +
        '<div class="wb-icon airdesk-title-icon"></div>' +
        '<div class="wb-title airdesk-title"></div>' +
      '</div>' +
      '<div class="airdesk-titlebar-actions"></div>' +
    '</div>' +
    '<div class="wb-body airdesk-window-body window-body"></div>' +
    '<div class="wb-n"></div><div class="wb-s"></div><div class="wb-w"></div><div class="wb-e"></div>' +
    '<div class="wb-nw"></div><div class="wb-ne"></div><div class="wb-se"></div><div class="wb-sw"></div>';
  return template;
}

class WindowHandle implements DesktopWindowHandle {
  private closedState = false;

  constructor(
    readonly id: string,
    private instance: WinBoxInstance,
    readonly element: HTMLElement,
    readonly body: HTMLElement,
    private insets: WindowInsets,
    private readonly onClosed: () => void
  ) {}

  get closed(): boolean {
    return this.closedState;
  }

  focus(): void {
    if (!this.closedState) this.instance.focus();
  }

  minimize(): void {
    if (!this.closedState) this.instance.minimize();
  }

  maximize(): void {
    if (this.closedState) return;
    const view = this.element.ownerDocument.defaultView;
    view?.dispatchEvent(new Event('resize'));
    this.instance.maximize();
  }

  restore(): void {
    if (!this.closedState) this.instance.restore();
  }

  close(): void {
    if (!this.closedState) this.instance.close();
  }

  setTitle(title: string): void {
    if (!this.closedState) this.instance.setTitle(title);
  }

  setBounds(bounds: WindowBounds): void {
    if (this.closedState) return;
    this.instance.resize(bounds.width, bounds.height).move(bounds.x, bounds.y);
  }

  setViewportInsets(insets: WindowInsets): void {
    if (this.closedState) return;
    const wasMaximized = this.instance.max;
    if (wasMaximized) this.instance.restore();
    this.insets = insets;
    this.applyInsets();
    if (wasMaximized) this.instance.maximize();
  }

  clientToWindowPoint(clientX: number, clientY: number): { x: number; y: number } {
    const rect = this.element.getBoundingClientRect();
    return {
      x: clientX - rect.left,
      y: clientY - rect.top
    };
  }

  markClosed(): void {
    this.closedState = true;
    this.onClosed();
  }

  applyInsets(): void {
    this.instance.top = this.insets.top;
    this.instance.right = this.insets.right;
    this.instance.bottom = this.insets.bottom;
    this.instance.left = this.insets.left;
    this.clampToViewport();
  }

  private clampToViewport(): void {
    if (this.instance.max || this.instance.min) return;
    const view = this.element.ownerDocument.defaultView;
    if (!view) return;

    const maxX = Math.max(
      this.insets.left,
      view.innerWidth - this.insets.right - Math.min(120, this.instance.width)
    );
    const maxY = Math.max(
      this.insets.top,
      view.innerHeight - this.insets.bottom - Math.min(80, this.instance.height)
    );
    const x = Math.min(Math.max(this.instance.x, this.insets.left), maxX);
    const y = Math.min(Math.max(this.instance.y, this.insets.top), maxY);
    if (x !== this.instance.x || y !== this.instance.y) this.instance.move(x, y);
  }
}

export class WinBoxWindowManager {
  private readonly windows = new Map<string, WindowHandle>();
  private readonly focusStack: string[] = [];
  private insets: WindowInsets;

  constructor(private readonly options: WindowManagerOptions) {
    this.insets = { ...DEFAULT_INSETS, ...options.insets };
  }

  open(descriptor: DesktopWindowDescriptor): DesktopWindowHandle {
    const existing = this.windows.get(descriptor.id);
    if (existing && !existing.closed) {
      existing.focus();
      return existing;
    }

    const document = this.options.document ?? this.options.root.ownerDocument;
    const template = createAirDeskWindowTemplate(document);
    const instance = this.options.factory({
      id: descriptor.id,
      root: this.options.root,
      title: descriptor.title,
      icon: descriptor.icon,
      template,
      x: descriptor.bounds.x,
      y: descriptor.bounds.y,
      width: descriptor.bounds.width,
      height: descriptor.bounds.height,
      minwidth: descriptor.minWidth ?? 380,
      minheight: descriptor.minHeight ?? 260,
      top: this.insets.top,
      right: this.insets.right,
      bottom: this.insets.bottom,
      left: this.insets.left,
      class: 'airdesk-window window',
      onfocus: () => {
        this.bringToFront(descriptor.id);
        descriptor.onFocus?.();
      },
      onblur: descriptor.onBlur,
      onmove: descriptor.onMove,
      onresize: descriptor.onResize,
      onminimize: () => {
        this.removeFromFocusStack(descriptor.id);
        descriptor.onMinimize?.();
      },
      onmaximize: descriptor.onMaximize,
      onrestore: descriptor.onRestore,
      onclose: () => {
        if (descriptor.onBeforeClose?.() === false) return true;
        this.remove(descriptor.id);
        descriptor.onClosed?.();
        return false;
      }
    });

    instance.dom.setAttribute('data-app', descriptor.id);
    instance.dom.setAttribute('role', 'dialog');
    instance.dom.setAttribute('aria-label', descriptor.appName ?? descriptor.title);

    if (descriptor.content instanceof Node) {
      instance.body.appendChild(descriptor.content);
    } else if (typeof descriptor.content === 'string') {
      instance.body.innerHTML = descriptor.content;
    }

    const handle = new WindowHandle(
      descriptor.id,
      instance,
      instance.dom,
      instance.body,
      this.insets,
      () => {
        this.windows.delete(descriptor.id);
        const index = this.focusStack.indexOf(descriptor.id);
        if (index >= 0) this.focusStack.splice(index, 1);
      }
    );

    this.wireChrome(instance, handle);
    this.windows.set(descriptor.id, handle);
    this.placeInFocusStack(descriptor.id);
    instance.focus();
    return handle;
  }

  get(id: string): DesktopWindowHandle | undefined {
    return this.windows.get(id);
  }

  getFocusOrder(): string[] {
    return [...this.focusStack];
  }

  topmost(): DesktopWindowHandle | undefined {
    const id = this.focusStack[this.focusStack.length - 1];
    return id ? this.windows.get(id) : undefined;
  }

  setViewportInsets(insets: Partial<WindowInsets>): void {
    this.insets = { ...this.insets, ...insets };
    for (const handle of this.windows.values()) {
      handle.setViewportInsets(this.insets);
    }
  }

  clientToWindowPoint(id: string, clientX: number, clientY: number): { x: number; y: number } | null {
    return this.windows.get(id)?.clientToWindowPoint(clientX, clientY) ?? null;
  }

  private wireChrome(instance: WinBoxInstance, handle: WindowHandle): void {
    for (const button of instance.dom.querySelectorAll<HTMLElement>('[data-window-action]')) {
      button.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        switch (button.dataset.windowAction) {
          case 'close':
            handle.close();
            break;
          case 'minimize':
            handle.minimize();
            break;
          case 'maximize':
            if (instance.max) {
              handle.restore();
            } else {
              handle.maximize();
            }
            break;
        }
      });
    }
  }

  private bringToFront(id: string): void {
    this.placeInFocusStack(id);
  }

  private placeInFocusStack(id: string): void {
    const index = this.focusStack.indexOf(id);
    if (index >= 0) this.focusStack.splice(index, 1);
    this.focusStack.push(id);
  }

  private removeFromFocusStack(id: string): void {
    const index = this.focusStack.indexOf(id);
    if (index >= 0) this.focusStack.splice(index, 1);
  }

  private remove(id: string): void {
    const handle = this.windows.get(id);
    if (!handle) return;
    this.windows.delete(id);
    handle.markClosed();
  }
}
