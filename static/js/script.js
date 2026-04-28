// Toggle Sidebar on Mobile
const menuToggle = document.getElementById('menu-toggle');
const sidebar = document.getElementById('sidebar');

function checkResponsive() {
    if (window.innerWidth <= 768) {
        menuToggle.style.display = 'block';
    } else {
        menuToggle.style.display = 'none';
        sidebar.classList.remove('active');
    }
}

window.addEventListener('resize', checkResponsive);
checkResponsive(); // Init

menuToggle.addEventListener('click', () => {
    sidebar.classList.toggle('active');
});

// Toast Notification Logic
function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');
    
    // Ocultar después de 3 segundos
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

// Interacción básica en la barra de búsqueda
const searchInput = document.querySelector('.search-input');
if(searchInput) {
    searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            showToast(`Buscando: "${searchInput.value}"...`);
        }
    });
}

/* =========================
   LÓGICA GESTIÓN DE USUARIOS
   ========================= */
document.addEventListener('DOMContentLoaded', function() {
    // Verificar si existen las pestañas en esta página antes de ejecutar
    const tabs = document.querySelectorAll('.tab-btn');
    const cards = document.querySelectorAll('.user-card-item');

    if (tabs.length > 0 && cards.length > 0) {
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                // Remover clase activa de todos
                tabs.forEach(t => t.classList.remove('active'));
                // Agregar activa al clickeado
                tab.classList.add('active');

                const filter = tab.getAttribute('data-filter');

                cards.forEach(card => {
                    if (filter === 'all' || card.getAttribute('data-role') === filter) {
                        card.style.display = 'flex';
                    } else {
                        card.style.display = 'none';
                    }
                });
            });
        });
    }
});

/* =========================
   LÓGICA MONITOREO IOT (Leaflet)
   ========================= */

// Referencia global al mapa para poder destruirlo antes de reinicializar
let iotMapInstance = null;

// Función para inicializar el mapa (se ejecuta solo si estamos en la página iot)
function initIoTMap() {
    // Verificar si existe el div del mapa
    const mapContainer = document.getElementById('map');
    if (!mapContainer) return;

    // Destruir instancia previa para evitar error "Map container already initialized"
    if (iotMapInstance) {
        iotMapInstance.remove();
        iotMapInstance = null;
    }

    // Coordenadas iniciales (Centro genérico, ej. Ciudad de México)
    const map = L.map('map').setView([19.4326, -99.1332], 13);
    iotMapInstance = map;

    // Capa del mapa (OpenStreetMap - Gratis)
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
    }).addTo(map);

    // Datos simulados de pacientes
    const patients = [
        { name: "Robert Miller", lat: 19.435, lng: -99.135, status: "critical", img: "https://picsum.photos/seed/robert/50/50" },
        { name: "Margaret T.", lat: 19.430, lng: -99.130, status: "safe", img: "https://picsum.photos/seed/margaret/50/50" },
        { name: "Evelyn R.", lat: 19.438, lng: -99.128, status: "critical", img: "https://picsum.photos/seed/evelyn/50/50" },
        { name: "Arthur T.", lat: 19.425, lng: -99.140, status: "warning", img: "https://picsum.photos/seed/arthurp/50/50" }
    ];

    // Iconos personalizados (CSS puro para evitar imágenes rotas)
    function createCustomIcon(color) {
        return L.divIcon({
            className: 'custom-div-icon',
            html: `<div style="background-color: ${color}; width: 16px; height: 16px; border-radius: 50%; border: 3px solid white; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>`,
            iconSize: [20, 20],
            iconAnchor: [10, 10]
        });
    }

    // Agregar marcadores
    patients.forEach(p => {
        let color = '#10B981'; // Verde (Safe)
        if (p.status === 'critical') color = '#EF4444'; // Rojo
        if (p.status === 'warning') color = '#F59E0B'; // Naranja

        const marker = L.marker([p.lat, p.lng], { icon: createCustomIcon(color) }).addTo(map);

        // Contenido del popup
        const popupContent = `
            <div class="popup-patient">
                <img src="${p.img}" alt="Pac">
                <h4>${p.name}</h4>
                <p>Estado: ${p.status.toUpperCase()}</p>
                <button class="popup-btn" onclick="showToast('Ver detalles de ${p.name}')">Ver Paciente</button>
            </div>
        `;
        marker.bindPopup(popupContent);
    });
}

// Ejecutar al cargar
document.addEventListener('DOMContentLoaded', () => {
    initIoTMap();
});

// Función para simular alerta flotante
function simulateAlert() {
    const alertBox = document.getElementById('floatingAlert');
    if(alertBox) {
        alertBox.classList.remove('hidden');
        showToast('¡Nueva Alerta de Zona detectada!');
    }
}

function hideFloatingAlert() {
    const alertBox = document.getElementById('floatingAlert');
    if(alertBox) {
        alertBox.classList.add('hidden');
    }
}

function resetMap() {
    showToast('Recargando datos del mapa...');
    // Aquí iría la lógica para refrescar los marcadores
    initIoTMap(); 
}

/* =========================
   LÓGICA REPORTES CLÍNICOS
   ========================= */

function generateReport() {
    const startDate = document.getElementById('startDate').value;
    const endDate = document.getElementById('endDate').value;
    const type = document.getElementById('scaleType').value;

    // Validación simple
    if (!startDate || !endDate) {
        alert("Por favor selecciona ambas fechas.");
        return;
    }

    if (new Date(startDate) > new Date(endDate)) {
        alert("La fecha de inicio no puede ser posterior a la fecha fin.");
        return;
    }

    // Simulación de proceso
    const btn = document.querySelector('#reportForm button[type="submit"]');
    const originalText = btn.innerHTML;
    
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Generando...';

    setTimeout(() => {
        btn.disabled = false;
        btn.innerHTML = originalText;
        
        showToast(`Reporte de "${type}" generado exitosamente.`);
        
        // Aquí podrías agregar lógica para insertar una fila nueva en la tabla dinámicamente
    }, 1500);
}

function resetReportForm() {
    document.getElementById('reportForm').reset();
    showToast("Filtros limpiados");
}

/* =========================
   LÓGICA LOG DE AUDITORÍA
   ========================= */

function filterAuditLogs() {
    const btn = document.querySelector('#auditForm button[type="submit"]');
    const originalText = btn.innerHTML;
    
    // Simular carga
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Filtrando...';

    setTimeout(() => {
        btn.disabled = false;
        btn.innerHTML = originalText;
        showToast("Registros filtrados exitosamente.");
        // Aquí iría la lógica real de filtrado de la tabla
    }, 1000);
}

function exportAuditLog() {
    showToast("Descargando archivo CSV de auditoría...");
    // Simular descarga
}