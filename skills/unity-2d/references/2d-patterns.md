# 2D Gameplay Patterns

Patterns de gameplay 2D complets pour Unity 6+. Chaque pattern est pret a copier-coller et utilise les APIs Unity 6 (`linearVelocity`, `Awaitable`, etc.).

---

## 1. Platformer 2D Controller

Controller complet avec : ground check, coyote time, jump buffer, hauteur de saut variable, multiplicateur de gravite en chute.

```csharp
using UnityEngine;

public class PlatformerController2D : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float moveSpeed = 8f;
    [SerializeField] private float acceleration = 60f;
    [SerializeField] private float deceleration = 50f;

    [Header("Jump")]
    [SerializeField] private float jumpForce = 14f;
    [SerializeField] private float fallGravityMultiplier = 2.5f;
    [SerializeField] private float lowJumpGravityMultiplier = 2f;
    [SerializeField] private float maxFallSpeed = -20f;

    [Header("Coyote Time & Jump Buffer")]
    [SerializeField] private float coyoteTime = 0.12f;
    [SerializeField] private float jumpBufferTime = 0.1f;

    [Header("Ground Check")]
    [SerializeField] private Transform groundCheckPoint;
    [SerializeField] private float groundCheckRadius = 0.15f;
    [SerializeField] private LayerMask groundLayer;

    private Rigidbody2D rb;
    private SpriteRenderer spriteRenderer;
    private float moveInput;
    private float coyoteTimer;
    private float jumpBufferTimer;
    private bool isGrounded;
    private bool isJumping;
    private float defaultGravityScale;

    private void Awake()
    {
        rb = GetComponent<Rigidbody2D>();
        spriteRenderer = GetComponent<SpriteRenderer>();
        defaultGravityScale = rb.gravityScale;
    }

    private void Update()
    {
        // Inputs dans Update, jamais dans FixedUpdate
        moveInput = Input.GetAxisRaw("Horizontal");

        // Ground check
        isGrounded = Physics2D.OverlapCircle(
            groundCheckPoint.position, groundCheckRadius, groundLayer);

        // Coyote time
        if (isGrounded)
        {
            coyoteTimer = coyoteTime;
            isJumping = false;
        }
        else
        {
            coyoteTimer -= Time.deltaTime;
        }

        // Jump buffer
        if (Input.GetButtonDown("Jump"))
            jumpBufferTimer = jumpBufferTime;
        else
            jumpBufferTimer -= Time.deltaTime;

        // Saut : coyote time + jump buffer
        if (jumpBufferTimer > 0f && coyoteTimer > 0f)
        {
            rb.linearVelocity = new Vector2(rb.linearVelocity.x, jumpForce);
            jumpBufferTimer = 0f;
            coyoteTimer = 0f;
            isJumping = true;
        }

        // Hauteur de saut variable : relacher = couper la velocite
        if (Input.GetButtonUp("Jump") && rb.linearVelocity.y > 0f)
        {
            rb.linearVelocity = new Vector2(
                rb.linearVelocity.x, rb.linearVelocity.y * 0.5f);
        }

        // Flip sprite
        if (moveInput != 0f)
            spriteRenderer.flipX = moveInput < 0f;
    }

    private void FixedUpdate()
    {
        // Mouvement horizontal avec acceleration/deceleration
        float targetSpeed = moveInput * moveSpeed;
        float speedDiff = targetSpeed - rb.linearVelocity.x;
        float accelRate = Mathf.Abs(targetSpeed) > 0.01f
            ? acceleration : deceleration;
        float movement = speedDiff * accelRate * Time.fixedDeltaTime;

        rb.linearVelocity = new Vector2(
            rb.linearVelocity.x + movement, rb.linearVelocity.y);

        // Gravite variable : plus lourde en chute, plus legere si jump maintenu
        if (rb.linearVelocity.y < 0f)
        {
            rb.gravityScale = defaultGravityScale * fallGravityMultiplier;
        }
        else if (rb.linearVelocity.y > 0f && !Input.GetButton("Jump"))
        {
            rb.gravityScale = defaultGravityScale * lowJumpGravityMultiplier;
        }
        else
        {
            rb.gravityScale = defaultGravityScale;
        }

        // Clamp vitesse de chute
        if (rb.linearVelocity.y < maxFallSpeed)
        {
            rb.linearVelocity = new Vector2(
                rb.linearVelocity.x, maxFallSpeed);
        }
    }

    private void OnDrawGizmosSelected()
    {
        if (groundCheckPoint == null) return;
        Gizmos.color = Color.red;
        Gizmos.DrawWireSphere(groundCheckPoint.position, groundCheckRadius);
    }
}
```

**Setup requis** :
- Rigidbody2D : Dynamic, Freeze Rotation Z, Interpolate
- Collider : CapsuleCollider2D
- Enfant vide `GroundCheck` positionne aux pieds du personnage
- LayerMask `Ground` assigne au Tilemap de collision

---

## 2. Top-Down 8-dir Movement

Mouvement 8 directions avec rotation douce vers la direction de deplacement. Ideal pour les jeux type Zelda, twin-stick, action RPG.

```csharp
using UnityEngine;

public class TopDownController2D : MonoBehaviour
{
    [SerializeField] private float moveSpeed = 6f;
    [SerializeField] private float rotationSpeed = 720f;

    private Rigidbody2D rb;
    private Vector2 moveInput;
    private Vector2 smoothedInput;
    private Vector2 inputVelocity;

    private void Awake()
    {
        rb = GetComponent<Rigidbody2D>();
        rb.gravityScale = 0f; // Pas de gravite en top-down
    }

    private void Update()
    {
        moveInput = new Vector2(
            Input.GetAxisRaw("Horizontal"),
            Input.GetAxisRaw("Vertical")
        ).normalized; // Normaliser pour eviter le speed boost en diagonale

        // Smooth input pour eviter les changements brusques
        smoothedInput = Vector2.SmoothDamp(
            smoothedInput, moveInput, ref inputVelocity, 0.05f);
    }

    private void FixedUpdate()
    {
        // Mouvement
        rb.linearVelocity = smoothedInput * moveSpeed;

        // Rotation vers la direction de mouvement
        if (moveInput.sqrMagnitude > 0.01f)
        {
            float targetAngle = Mathf.Atan2(moveInput.y, moveInput.x)
                * Mathf.Rad2Deg - 90f;
            float angle = Mathf.MoveTowardsAngle(
                rb.rotation, targetAngle,
                rotationSpeed * Time.fixedDeltaTime);
            rb.MoveRotation(angle);
        }
    }
}
```

**Setup requis** :
- Rigidbody2D : Dynamic, Gravity Scale = 0, Interpolate
- Collider : CircleCollider2D ou CapsuleCollider2D
- Physics Material 2D : Friction = 0, Bounciness = 0

---

## 3. Parallax Scrolling

Defilement parallaxe avec boucle infinie. Chaque couche se deplace a une vitesse differente selon sa "profondeur".

```csharp
using UnityEngine;

public class ParallaxLayer : MonoBehaviour
{
    [Tooltip("0 = fixe (fond lointain), 1 = suit la camera (premier plan)")]
    [Range(0f, 1f)]
    [SerializeField] private float parallaxEffect = 0.5f;

    [SerializeField] private bool infiniteLoop = true;

    private Transform cameraTransform;
    private float startPosX;
    private float spriteWidth;
    private Vector3 lastCameraPos;

    private void Start()
    {
        cameraTransform = Camera.main.transform;
        lastCameraPos = cameraTransform.position;
        startPosX = transform.position.x;

        if (infiniteLoop)
        {
            var sr = GetComponent<SpriteRenderer>();
            spriteWidth = sr.bounds.size.x;
        }
    }

    private void LateUpdate()
    {
        Vector3 cameraDelta = cameraTransform.position - lastCameraPos;
        transform.position += new Vector3(
            cameraDelta.x * parallaxEffect,
            cameraDelta.y * parallaxEffect,
            0f);
        lastCameraPos = cameraTransform.position;

        // Boucle infinie : teleporter quand on depasse la largeur du sprite
        if (!infiniteLoop) return;

        float relativePos = cameraTransform.position.x - transform.position.x;
        if (relativePos > spriteWidth * 0.5f)
            transform.position += new Vector3(spriteWidth, 0f, 0f);
        else if (relativePos < -spriteWidth * 0.5f)
            transform.position -= new Vector3(spriteWidth, 0f, 0f);
    }
}
```

**Setup** :
- Creer 3-5 sprites d'arriere-plan sur des Sorting Layers separes
- Assigner un `parallaxEffect` croissant (0.1 pour le ciel, 0.9 pour le premier plan)
- Activer `infiniteLoop` pour les couches qui doivent boucler
