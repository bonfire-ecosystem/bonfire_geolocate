let use_vector = false;
let mapbox_token = "pk.eyJ1IjoibWF5ZWwiLCJhIjoiY2tlMmxzNXF5MGFpaDJ0bzR2M29id2EzOCJ9.QsmjD-zypsE0_wonLGCYlA";
// TODO: read the token from env/config

import L from "leaflet";
import "mapbox-gl";
import "mapbox-gl-leaflet";
import "./leaflet-marker";
import "./leaflet-icon";

let ExtensionHooks = {};

ExtensionHooks.MapLeaflet = {
  mounted() {
    const view = this;

    const template = document.createElement("template");
    // Warning: remember to update the stylesheet version at the same time as the JS
    template.innerHTML = `
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.7.1/dist/leaflet.css" crossorigin=""/>
    <div style="height: 100%; min-height: 420px;">
        <slot />
    </div>`;

    const maybe_map_moved = function (e) {
      var bounds = createPolygonFromBounds(e.target, e.target.getBounds());
      console.log(bounds);
      view.pushEvent("map_bounds", bounds._latlngs);
    };

    /// Takes an L.latLngBounds object and returns an 8 point L.polygon.
    /// L.rectangle takes an L.latLngBounds object in its constructor but this only creates a polygon with 4 points.
    /// This becomes an issue when you try and do spatial queries in SQL because when the 4 point polygon is applied
    /// to the curvature of the earth it loses it's "rectangular-ness".
    /// The 8 point polygon returned from this method will keep it's shape a lot more.
    /// <param name="map">L.map object</param>
    /// <returns type="">L.Polygon with 8 points starting in the bottom left and finishing in the center left</returns>
    const createPolygonFromBounds = function (map, latLngBounds) {
      var center = latLngBounds.getCenter();
      var map_center = map.getCenter();
      var latlngs = [];

      latlngs.push(latLngBounds.getSouthWest()); //bottom left
      latlngs.push({ lat: latLngBounds.getSouth(), lng: center.lng }); //bottom center
      latlngs.push(latLngBounds.getSouthEast()); //bottom right
      latlngs.push({ lat: center.lat, lng: latLngBounds.getEast() }); // center right
      latlngs.push(latLngBounds.getNorthEast()); //top right
      latlngs.push({ lat: latLngBounds.getNorth(), lng: map_center.lng }); //top center
      latlngs.push(latLngBounds.getNorthWest()); //top left
      latlngs.push({ lat: map_center.lat, lng: latLngBounds.getWest() }); //center left

      return new L.polygon(latlngs);
    };

    class LeafletMap extends HTMLElement {
      constructor() {
        super();

        this.attachShadow({ mode: "open" });
        this.shadowRoot.appendChild(template.content.cloneNode(true));
        this.mapElement = this.shadowRoot.querySelector("div");

        var bounds = new L.LatLngBounds(
          JSON.parse(this.getAttribute("points"))
        );
        console.log(this.getAttribute("points"))
        console.log(bounds)

        this.map = L.map(this.mapElement).fitBounds(bounds);

        // this.map = L.map(this.mapElement).setView(
        //   [this.getAttribute("lat"), this.getAttribute("lng")],
        //   13
        // );
        console.log(use_vector)
        this.map.options.minZoom = 2;
        if(!use_vector){ 
          
          console.log("map: use tiles")

          L.tileLayer(
            "https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
            {
              attribution:
                'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
              maxZoom: 18,
              id: "mapbox/streets-v11",
              tileSize: 512,
              zoomOffset: -1,
              accessToken: mapbox_token,
              crossOrigin: ""
            }
          ).addTo(this.map);

        } else { 

          console.log("map: use vectors from openmaptiles.org")

          this.map.options.minZoom = 4;
          
          // L.tileLayer('https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}', {
          //     attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
          //     maxZoom: 18,
          //     id: 'mapbox/streets-v11',
          //     tileSize: 512,
          //     zoomOffset: -1,
          //     accessToken: 'your.mapbox.access.token'
          // }).addTo(mymap);


          L.mapboxGL({
              accessToken: mapbox_token,
              style: 'mapbox://styles/mapbox/streets-v11', // style URL
              // style: 'https://openmaptiles.github.io/maptiler-toner-gl-style/style-cdn.json'
              // style: 'https://openmaptiles.github.io/maptiler-terrain-gl-style/style-cdn.json'
              // style: 'https://maputnik.github.io/osm-liberty/style.json'
              // style: 'https://openmaptiles.github.io/maptiler-basic-gl-style/style-cdn.json'
              // style: 'https://openmaptiles.github.io/osm-bright-gl-style/style-cdn.json'
              // style: 'https://openmaptiles.github.io/maptiler-3d-gl-style/style-cdn.json'
          }).addTo(this.map);

          this.map.fitWorld();

        }

        this.map.on("moveend", maybe_map_moved);
        this.map.on("zoomend", maybe_map_moved);

        this.defaultIcon = L.icon({
          iconUrl: "https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon.png",
          // iconSize: [32, 32],
        });
      }

      connectedCallback() {
        const markerElements = this.querySelectorAll("leaflet-marker");
        markerElements.forEach((markerEl) => {
          const lat = markerEl.getAttribute("lat");
          const lng = markerEl.getAttribute("lng");

          const marker = L.marker([lat, lng], {
            icon: this.defaultIcon,
          }).addTo(this.map);

          const popup = markerEl.getAttribute("popup");

          if (popup) {
            marker.bindPopup(popup);

            marker.on("click", function (e) {
              this.openPopup();
            });
            // marker.on("mouseout", function (e) {
            //   this.closePopup();
            // });
          }

          // marker.addEventListener("click", (_event) => {
          //   markerEl.click();
          // });

          const iconEl = markerEl.querySelector("leaflet-icon");
          const iconSize = [
            iconEl.getAttribute("width"),
            iconEl.getAttribute("height"),
          ];

          // iconEl.addEventListener("url-updated", (e) => {
          //   marker.setIcon(
          //     L.icon({
          //       iconUrl: e.detail,
          //       iconSize: iconSize,
          //       iconAnchor: iconSize,
          //     })
          //   );
          // });
        });
      }
    }

    window.customElements.define("leaflet-map", LeafletMap);
  },
};

export { ExtensionHooks }